// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

const std = @import("std");
const handler = @import("varlink-handler");
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
            response_stream: anytype,
            options: handler.Options,
            extra_info: u32,
        ) !void {
            context.counter += 1;
            if (options.oneway) {
                return;
            }
            try handler.serializeResponse(response_stream, zigVarlinkTest.TestCall.ReturnType{
                .out = parameters.in + context.counter + extra_info,
            });
        }
    } = .{},
};

test "Varlink handler works correctly" {
    var context: Context = .{};
    var buffer: [4096]u8 = undefined;
    {
        var response_stream = std.io.fixedBufferStream(&buffer);
        const request =
            \\{
            \\  "method": "org.varlink.service.GetInfo",
            \\  "parameters": {"interface": "org.varlink.service"}
            \\}
        ;
        try handler.handleRequest(request, response_stream.writer(), std.testing.allocator, &context, 5);
        try std.testing.expectEqualStrings(
            \\{"parameters":{"vendor":"test","product":"test","version":"0.1","url":"http://example.com/","interfaces":["org.varlink.service","org.zig-varlink.test"]}}
        , response_stream.getWritten());
    }
    {
        var response_stream = std.io.fixedBufferStream(&buffer);
        const request =
            \\{
            \\  "method": "org.zig-varlink.test.TestCall",
            \\  "parameters": {"in": 2}
            \\}
        ;
        try handler.handleRequest(request, response_stream.writer(), std.testing.allocator, &context, 5);
        try std.testing.expectEqualStrings(
            \\{"parameters":{"out":8}}
        , response_stream.getWritten());
    }
}
