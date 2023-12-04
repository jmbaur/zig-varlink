// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

const std = @import("std");
const handler = @import("varlink-handler");
const client = @import("varlink-client");
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

fn handleRequest(stream: std.net.Stream, reader: anytype, context: *ServerContext, client_id: []const u8) !void {
    var request_buffer: [4096]u8 = undefined;
    var write_buffer: [4096]u8 = undefined;
    var write_stream = std.io.fixedBufferStream(&write_buffer);
    const request = try readMessage(reader, &request_buffer);
    try handler.handleRequest(
        request,
        write_stream.writer(),
        gpa,
        context,
        client_id,
    );
    if (write_stream.pos != 0) {
        try write_stream.writer().writeByte(0);
        try stream.writeAll(write_stream.getWritten());
    }
}

fn handleResponse(reader: anytype, state: anytype) !void {
    var request_buffer: [4096]u8 = undefined;
    const response = try readMessage(reader, &request_buffer);
    try state.handleResponse(response, gpa);
}

const Arguments = struct {
    address: std.net.Address,
    client: bool,

    const ParseTcpError = error{
        MissingClosingBracket,
        MissingPort,
        InvalidPort,
        InvalidAddress,
    };

    fn parseTcp(address: []const u8) ParseTcpError!std.net.Address {
        if (address[0] == '[') {
            const ipv6_end = std.mem.indexOfScalar(u8, address, ']') orelse
                return error.MissingClosingBracket;
            if (ipv6_end >= address.len - 2 or address[ipv6_end + 1] != ':') {
                return error.MissingPort;
            }
            const port = std.fmt.parseInt(u16, address[ipv6_end + 2 ..], 10) catch
                return error.InvalidPort;
            return std.net.Address.parseIp6(address[1..ipv6_end], port) catch error.InvalidAddress;
        } else {
            const colon_position = std.mem.indexOfScalar(u8, address, ':') orelse
                return error.MissingPort;
            if (colon_position == address.len - 1) {
                return error.MissingPort;
            }
            const port = std.fmt.parseInt(u16, address[colon_position + 1 ..], 10) catch
                return error.InvalidPort;
            return std.net.Address.parseIp4(address[0..colon_position], port) catch error.InvalidAddress;
        }
    }

    test "parseTcp can handle IPv4" {
        {
            const address = "127.0.0.1:1234";
            const parsed = try parseTcp(address);
            const string_form = try std.fmt.allocPrint(
                std.testing.allocator,
                "{}",
                .{parsed},
            );
            defer std.testing.allocator.free(string_form);
            try std.testing.expectEqualStrings("127.0.0.1:1234", string_form);
        }
        {
            const address = "127.0.0.1";
            try std.testing.expectError(error.MissingPort, parseTcp(address));
        }
        {
            const address = "127.0.0.1:";
            try std.testing.expectError(error.MissingPort, parseTcp(address));
        }
        {
            const address = "127.0.0.1:-1";
            try std.testing.expectError(error.InvalidPort, parseTcp(address));
        }
        {
            const address = "609.609.609.609:0";
            try std.testing.expectError(error.InvalidAddress, parseTcp(address));
        }
    }

    test "parseTcp can handle IPv6" {
        {
            const address = "[::1]:1234";
            const parsed = try parseTcp(address);
            const string_form = try std.fmt.allocPrint(
                std.testing.allocator,
                "{}",
                .{parsed},
            );
            defer std.testing.allocator.free(string_form);
            try std.testing.expectEqualStrings("[::1]:1234", string_form);
        }
        {
            const address = "[::1]";
            try std.testing.expectError(error.MissingPort, parseTcp(address));
        }
        {
            const address = "[::1]:";
            try std.testing.expectError(error.MissingPort, parseTcp(address));
        }
        {
            const address = "[::1]:-1";
            try std.testing.expectError(error.InvalidPort, parseTcp(address));
        }
        {
            const address = "[:::1]:0";
            try std.testing.expectError(error.InvalidAddress, parseTcp(address));
        }
        {
            const address = "[::1";
            try std.testing.expectError(error.MissingClosingBracket, parseTcp(address));
        }
    }

    const ParseAddressError = ParseTcpError || error{
        MissingAddress,
        UnknownScheme,
        MissingColon,
    };

    fn parseAddress(address: []const u8) ParseAddressError!std.net.Address {
        // TODO: How can a semicolon be escaped?
        const semicolon_pos = std.mem.indexOfScalar(u8, address, ';') orelse address.len;
        const effective_address = address[0..semicolon_pos];
        const colon_pos = std.mem.indexOfScalar(u8, effective_address, ':');
        if (colon_pos) |colon_position| {
            if (colon_pos == effective_address.len - 1) {
                return error.MissingAddress;
            }
            const scheme = effective_address[0..colon_position];
            if (std.mem.eql(u8, "tcp", scheme)) {
                return parseTcp(effective_address[colon_position + 1 ..]);
            } else {
                return error.UnknownScheme;
            }
        } else {
            return error.MissingColon;
        }
    }

    test parseAddress {
        const address = "tcp:127.0.0.1:1234;options=123";
        const parsed = try parseAddress(address);
        const string_form = try std.fmt.allocPrint(
            std.testing.allocator,
            "{}",
            .{parsed},
        );
        defer std.testing.allocator.free(string_form);
        try std.testing.expectEqualStrings("127.0.0.1:1234", string_form);
    }

    test "parseAddress reports errors correctly" {
        {
            const address = "tcp";
            try std.testing.expectError(error.MissingColon, parseAddress(address));
        }
        {
            const address = "tcp:";
            try std.testing.expectError(error.MissingAddress, parseAddress(address));
        }
        {
            const address = "udp:127.0.0.1:0";
            try std.testing.expectError(error.UnknownScheme, parseAddress(address));
        }
    }

    fn parseArgument(writer: anytype, argument: []const u8, arguments: *Arguments) !void {
        if (std.mem.eql(u8, "--client", argument)) {
            arguments.client = true;
            return;
        }
        const expected_prefix = "--varlink=";
        if (std.mem.startsWith(u8, argument, expected_prefix)) {
            const address = argument[expected_prefix.len..];
            const parsed_address = parseAddress(address) catch |err| {
                try writer.print("Failed to parse Varlink address: {}\n", .{err});
                return error.InvalidArguments;
            };
            arguments.address = parsed_address;
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

fn callStart(state: anytype, writer: anytype, allocator: std.mem.Allocator) !void {
    try state.serializeRequest(
        writer,
        .@"org.varlink.certification.Start",
        .{},
        .{},
        allocator,
    );
    try writer.writeByte(0);
}

fn runClient(address: std.net.Address) !void {
    var connection = try std.net.tcpConnectToAddress(address);
    defer connection.close();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    var write_buffer = std.io.bufferedWriter(connection.writer());
    const writer = write_buffer.writer();
    var context: ClientContext = .{
        .@"org.varlink.certification" = .{
            .allocator = allocator,
            .request_stream = writer,
        },
    };
    defer context.@"org.varlink.certification".deinit();
    var state = client.Client(ClientContext).init(&context, gpa);
    defer state.deinit();
    try callStart(&state, write_buffer.writer(), allocator);
    try write_buffer.flush();
    var read_buffer = std.io.bufferedReader(connection.reader());
    while (!context.@"org.varlink.certification".done) {
        try handleResponse(read_buffer.reader(), &state);
        try write_buffer.flush();
    }
}

fn runServer(stderr_buf: anytype, address: std.net.Address) !void {
    var server = std.net.StreamServer.init(.{ .reuse_address = true });
    defer server.deinit();
    try server.listen(address);
    try stderr_buf.writer().print("Listening to {}\n", .{server.listen_address});
    try stderr_buf.flush();

    const connection = try server.accept();
    defer connection.stream.close();
    var read_buffer = std.io.bufferedReader(connection.stream.reader());
    var raw_client_id: [16]u8 = undefined;
    try std.os.getrandom(&raw_client_id);
    var client_id_buf: [32]u8 = undefined;
    _ = std.fmt.bufPrint(
        &client_id_buf,
        "{}",
        .{std.fmt.fmtSliceHexLower(&raw_client_id)},
    ) catch unreachable;
    var context: ServerContext = .{};
    while (!context.@"org.varlink.certification".done) {
        try handleRequest(connection.stream, read_buffer.reader(), &context, &client_id_buf);
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
        std.os.exit(1);
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
    var response_stream: std.fifo.LinearFifo(u8, .{ .Static = 4096 }) = .{
        .buf = undefined,
        .allocator = {},
        .head = 0,
        .count = 0,
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var client_context: ClientContext = .{
        .@"org.varlink.certification" = .{
            .allocator = allocator,
            .request_stream = request_stream.writer(),
        },
    };
    defer client_context.@"org.varlink.certification".deinit();
    var client_state = client.Client(ClientContext).init(&client_context, std.testing.allocator);
    defer client_state.deinit();
    try callStart(&client_state, request_stream.writer(), allocator);

    var server_context: ServerContext = .{};
    while (!server_context.@"org.varlink.certification".done and
        !client_context.@"org.varlink.certification".done)
    {
        while (request_stream.count > 0) {
            const request = try readMessage(request_stream.reader(), &request_buffer);
            const old_count = response_stream.count;
            try handler.handleRequest(
                request,
                response_stream.writer(),
                std.testing.allocator,
                &server_context,
                "1234",
            );
            if (response_stream.count != old_count) {
                try response_stream.writer().writeByte(0);
            }
        }
        while (response_stream.count > 0) {
            const response = try readMessage(response_stream.reader(), &response_buffer);
            try client_state.handleResponse(response, std.testing.allocator);
        }
    }
    try std.testing.expect(server_context.@"org.varlink.certification".done);
    try std.testing.expect(client_context.@"org.varlink.certification".done);
}
