// SPDX-FileCopyrightText: 2023, 2026 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

const std = @import("std");
const varlink = @import("varlink");
const server = varlink.server;
const Client = varlink.Client;
const orgVarlinkCertification = @import("orgVarlinkCertification");
const gpa = std.heap.c_allocator;

const ServerContext = @import("server.zig");
const ClientContext = @import("client.zig");

fn readMessage(reader: *std.Io.Reader) ![]u8 {
    const res = try reader.takeDelimiterExclusive(0);
    reader.toss(1);
    return res;
}

const ServerConnection = server.Connection(
    ServerContext,
    []const u8,
);

fn handleRequest(
    connection: *ServerConnection,
    reader: anytype,
    context: *ServerContext,
) !void {
    const request = try readMessage(reader);
    try connection.handleRequest(
        request,
        gpa,
        context,
    );
}

fn handleResponse(reader: *std.Io.Reader, state: anytype) !void {
    const response = try readMessage(reader);
    try state.handleResponse(response);
}

const Arguments = struct {
    address: std.net.Address,
    client: bool,

    fn parseArgument(writer: *std.Io.Writer, argument: []const u8, arguments: *Arguments) !void {
        if (std.mem.eql(u8, "--client", argument)) {
            arguments.client = true;
            return;
        }
        const expected_prefix = "--varlink=";
        if (std.mem.startsWith(u8, argument, expected_prefix)) {
            const address = argument[expected_prefix.len..];
            const parsed_address = varlink.Address.parse(address) catch |err| {
                try writer.print("Failed to parse Varlink address: {}\n", .{err});
                return error.InvalidArguments;
            };
            if (parsed_address != .tcp) {
                try writer.writeAll("Expected a TCP address\n");
                return error.InvalidArguments;
            }
            arguments.address = parsed_address.tcp.toNetAddress();
            return;
        } else {
            try writer.print("Unexpected argument: {s}\n", .{argument});
            return error.InvalidArguments;
        }
    }

    fn parse(writer: *std.Io.Writer, args: *std.process.ArgIterator) !Arguments {
        if (!args.skip()) {
            try writer.writeAll("Missing program name as first argument!\n");
            return error.InvalidArguments;
        }
        var arguments: Arguments = .{
            .address = std.net.Address.initIp4(
                .{ 127, 0, 0, 1 },
                23456,
            ),
            .client = false,
        };

        while (args.next()) |arg| {
            try parseArgument(writer, arg, &arguments);
        }
        return arguments;
    }
};

fn callStart(state: anytype) !void {
    try state.serializeRequest(
        .@"org.varlink.certification.Start",
        .{},
        .{},
    );
}

fn runClient(address: std.net.Address) !void {
    var connection = try std.net.tcpConnectToAddress(address);
    defer connection.close();

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var write_buffer: [4096]u8 = undefined;
    var writer = connection.writer(&write_buffer);
    var context: ClientContext = .{
        .@"org.varlink.certification" = .{
            .allocator = allocator,
        },
    };
    defer context.@"org.varlink.certification".deinit();
    var state = Client(ClientContext).init(&context, &writer.interface, gpa);
    defer state.deinit();
    try callStart(&state);
    try writer.interface.flush();

    var read_buffer: [1024]u8 = undefined;
    var reader = connection.reader(&read_buffer);
    while (!context.@"org.varlink.certification".done) {
        try handleResponse(reader.interface(), &state);
        try writer.interface.flush();
    }
}

fn runServer(stderr: *std.Io.Writer, address: std.net.Address) !void {
    var socket_server = try address.listen(.{ .reuse_address = true });
    defer socket_server.deinit();
    try stderr.print("Listening to {f}\n", .{socket_server.listen_address});
    try stderr.flush();

    const connection = try socket_server.accept();
    defer connection.stream.close();

    var read_buffer: [1024]u8 = undefined;
    var reader = connection.stream.reader(&read_buffer);
    var raw_client_id: [16]u8 = undefined;
    try std.posix.getrandom(&raw_client_id);
    var client_id_buf: [32]u8 = undefined;
    _ = std.fmt.bufPrint(
        &client_id_buf,
        "{x}",
        .{&raw_client_id},
    ) catch unreachable;
    var context: ServerContext = .{};

    var write_buffer: [1024]u8 = undefined;
    var writer = connection.stream.writer(&write_buffer);
    var varlink_connection: ServerConnection = .{
        .response_writer = &writer.interface,
        .data = &client_id_buf,
    };

    while (!context.@"org.varlink.certification".done) {
        try handleRequest(
            &varlink_connection,
            reader.interface(),
            &context,
        );
        try writer.interface.flush();
    }
}

pub fn main() !void {
    var stderr_buffer: [256]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    const arguments = Arguments.parse(stderr, &args) catch {
        try stderr.flush();
        std.process.exit(1);
    };
    if (arguments.client) {
        try runClient(arguments.address);
    } else {
        try runServer(stderr, arguments.address);
    }
}

test {
    _ = Arguments;
}

test "Client and server can communicate with each other" {
    var request_buffer: [4096]u8 = undefined;
    var request_writer = std.Io.Writer.fixed(&request_buffer);
    var response_buffer: [4096]u8 = undefined;
    var response_writer = std.Io.Writer.fixed(&response_buffer);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var client_context: ClientContext = .{
        .@"org.varlink.certification" = .{
            .allocator = allocator,
        },
    };
    defer client_context.@"org.varlink.certification".deinit();
    var client_state = Client(ClientContext).init(
        &client_context,
        &request_writer,
        std.testing.allocator,
    );
    defer client_state.deinit();
    try callStart(&client_state);

    var server_context: ServerContext = .{};
    var server_connection = server.createConnection(
        ServerContext,
        &response_writer,
        []const u8,
        "1234",
    );
    while (!server_context.@"org.varlink.certification".done and
        !client_context.@"org.varlink.certification".done)
    {
        var request_reader = std.Io.Reader.fixed(request_writer.buffered());
        while (request_reader.bufferedLen() > 0) {
            const request = try readMessage(&request_reader);
            try server_connection.handleRequest(
                request,
                std.testing.allocator,
                &server_context,
            );
        }
        _ = request_writer.consumeAll();
        var response_reader = std.Io.Reader.fixed(response_writer.buffered());
        while (response_reader.bufferedLen() > 0) {
            const response = try readMessage(&response_reader);
            try client_state.handleResponse(response);
        }
        _ = response_writer.consumeAll();
    }
    try std.testing.expect(server_context.@"org.varlink.certification".done);
    try std.testing.expect(client_context.@"org.varlink.certification".done);
}
