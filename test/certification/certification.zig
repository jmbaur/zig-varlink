// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
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

fn readMessage(reader: anytype, message_buffer: []u8) ![]u8 {
    var read_stream = std.io.fixedBufferStream(message_buffer);
    try reader.streamUntilDelimiter(
        read_stream.writer(),
        0,
        null,
    );
    return read_stream.getWritten();
}

const ServerConnection = server.Connection(
    ServerContext,
    varlink.json.TrailingZeroWriter(
        std.io.BufferedWriter(4096, std.net.Stream.Writer).Writer,
    ),
    []const u8,
);

fn handleRequest(
    connection: *ServerConnection,
    reader: anytype,
    context: *ServerContext,
) !void {
    var request_buffer: [4096]u8 = undefined;
    const request = try readMessage(reader, &request_buffer);
    try connection.handleRequest(
        request,
        gpa,
        context,
    );
}

fn handleResponse(reader: anytype, state: anytype) !void {
    var request_buffer: [4096]u8 = undefined;
    const response = try readMessage(reader, &request_buffer);
    try state.handleResponse(response);
}

const Arguments = struct {
    address: std.net.Address,
    client: bool,

    fn parseArgument(writer: anytype, argument: []const u8, arguments: *Arguments) !void {
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

    fn parse(writer: anytype, args: *std.process.ArgIterator) !Arguments {
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
    var write_buffer = std.io.bufferedWriter(connection.writer());
    const writer = varlink.json.trailingZeroWriter(write_buffer.writer());
    var context: ClientContext = .{
        .@"org.varlink.certification" = .{
            .allocator = allocator,
        },
    };
    defer context.@"org.varlink.certification".deinit();
    var state = Client(ClientContext, @TypeOf(writer)).init(&context, writer, gpa);
    defer state.deinit();
    try callStart(&state);
    try write_buffer.flush();
    var read_buffer = std.io.bufferedReader(connection.reader());
    while (!context.@"org.varlink.certification".done) {
        try handleResponse(read_buffer.reader(), &state);
        try write_buffer.flush();
    }
}

fn runServer(stderr_buf: anytype, address: std.net.Address) !void {
    var socket_server = try address.listen(.{ .reuse_address = true });
    defer socket_server.deinit();
    try stderr_buf.writer().print("Listening to {}\n", .{socket_server.listen_address});
    try stderr_buf.flush();

    const connection = try socket_server.accept();
    defer connection.stream.close();
    var read_buffer = std.io.bufferedReader(connection.stream.reader());
    var raw_client_id: [16]u8 = undefined;
    try std.posix.getrandom(&raw_client_id);
    var client_id_buf: [32]u8 = undefined;
    _ = std.fmt.bufPrint(
        &client_id_buf,
        "{}",
        .{std.fmt.fmtSliceHexLower(&raw_client_id)},
    ) catch unreachable;
    var context: ServerContext = .{};

    var write_buffer = std.io.bufferedWriter(connection.stream.writer());
    var varlink_connection: ServerConnection = .{
        .response_writer = .{ .writer = write_buffer.writer() },
        .data = &client_id_buf,
    };

    while (!context.@"org.varlink.certification".done) {
        try handleRequest(
            &varlink_connection,
            read_buffer.reader(),
            &context,
        );
        try write_buffer.flush();
    }
}

pub fn main() !void {
    const stderr = std.io.getStdErr();
    var stderr_buf = std.io.bufferedWriter(stderr.writer());
    const stderr_writer = stderr_buf.writer();

    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    const arguments = Arguments.parse(stderr_writer, &args) catch {
        try stderr_buf.flush();
        std.process.exit(1);
    };
    if (arguments.client) {
        try runClient(arguments.address);
    } else {
        try runServer(&stderr_buf, arguments.address);
    }
}

test {
    _ = Arguments;
}

test "Client and server can communicate with each other" {
    var request_buffer: [4096]u8 = undefined;
    var response_buffer: [4096]u8 = undefined;
    var request_stream: std.fifo.LinearFifo(u8, .{ .Static = 4096 }) = .{
        .buf = undefined,
        .allocator = {},
        .head = 0,
        .count = 0,
    };
    const request_writer = varlink.json.trailingZeroWriter(request_stream.writer());
    var response_stream: std.fifo.LinearFifo(u8, .{ .Static = 4096 }) = .{
        .buf = undefined,
        .allocator = {},
        .head = 0,
        .count = 0,
    };
    const response_writer = varlink.json.trailingZeroWriter(response_stream.writer());

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var client_context: ClientContext = .{
        .@"org.varlink.certification" = .{
            .allocator = allocator,
        },
    };
    defer client_context.@"org.varlink.certification".deinit();
    var client_state = Client(ClientContext, @TypeOf(request_writer)).init(
        &client_context,
        request_writer,
        std.testing.allocator,
    );
    defer client_state.deinit();
    try callStart(&client_state);

    var server_context: ServerContext = .{};
    var server_connection = server.createConnection(
        ServerContext,
        response_writer,
        []const u8,
        "1234",
    );
    while (!server_context.@"org.varlink.certification".done and
        !client_context.@"org.varlink.certification".done)
    {
        while (request_stream.count > 0) {
            const request = try readMessage(request_stream.reader(), &request_buffer);
            try server_connection.handleRequest(
                request,
                std.testing.allocator,
                &server_context,
            );
        }
        while (response_stream.count > 0) {
            const response = try readMessage(response_stream.reader(), &response_buffer);
            try client_state.handleResponse(response);
        }
    }
    try std.testing.expect(server_context.@"org.varlink.certification".done);
    try std.testing.expect(client_context.@"org.varlink.certification".done);
}
