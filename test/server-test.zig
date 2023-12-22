// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

const std = @import("std");
const varlink = @import("varlink");
const server = varlink.server;
const Options = varlink.Options;
const zigVarlinkTest = @import("zigVarlinkTest");

const Context = struct {
    pub const vendor = "test";
    pub const product = "test";
    pub const version = "0.1";
    pub const url = "http://example.com/";
    @"org.zig-varlink.test": struct {
        pub const interface = zigVarlinkTest;
        counter: u32 = 0,
        pub fn handleTestCall(
            context: *@This(),
            parameters: zigVarlinkTest.TestCall.Parameters,
            request_context: anytype,
        ) !void {
            context.counter += 1;
            try std.testing.expectEqual(@TypeOf(parameters.choice).a, parameters.choice);
            try request_context.serializeResponse(.{
                .out = parameters.in +
                    context.counter +
                    request_context.getData(),
            });
        }
    } = .{},
};

test "Varlink handler works correctly" {
    var context: Context = .{};
    var buffer: [4096]u8 = undefined;
    {
        var response_stream = std.io.fixedBufferStream(&buffer);
        var response_writer = varlink.json.trailingZeroWriter(response_stream.writer());
        var connection = server.createConnection(Context, response_writer, u32, 5);
        const request =
            \\{
            \\  "method": "org.varlink.service.GetInfo",
            \\  "parameters": {"interface": "org.varlink.service"}
            \\}
        ;
        try connection.handleRequest(request, std.testing.allocator, &context);
        try std.testing.expectEqualStrings(
            \\{"parameters":{"vendor":"test","product":"test","version":"0.1","url":"http://example.com/","interfaces":["org.varlink.service","org.zig-varlink.test"]}}
        ++ "\x00", response_stream.getWritten());
    }
    {
        var response_stream = std.io.fixedBufferStream(&buffer);
        var response_writer = varlink.json.trailingZeroWriter(response_stream.writer());
        var connection = server.createConnection(Context, response_writer, u32, 5);
        const request =
            \\{
            \\  "method": "org.zig-varlink.test.TestCall",
            \\  "parameters": {"in": 2, "choice": "a"}
            \\}
        ;
        try connection.handleRequest(request, std.testing.allocator, &context);
        try std.testing.expectEqualStrings(
            \\{"parameters":{"out":8}}
        ++ "\x00", response_stream.getWritten());
    }
}
