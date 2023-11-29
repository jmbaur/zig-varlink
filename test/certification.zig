// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

const std = @import("std");
const handler = @import("varlink-handler");
const orgVarlinkCertification = @import("orgVarlinkCertification");
const gpa = std.heap.c_allocator;

const Context = struct {
    pub const vendor = "zig-varlink";
    pub const product = "Varlink certification";
    pub const version = "1";
    pub const url = "https://sr.ht/~mainiomano/zig-varlink/";

    @"org.varlink.certification": struct {
        pub const interface = orgVarlinkCertification;

        // TODO: Actually limit to methods?
        const Method = std.meta.DeclEnum(orgVarlinkCertification);
        next_method: Method = .Start,
        done: bool = false,

        fn checkParameters(
            expected: anytype,
            actual: @TypeOf(expected),
            response_stream: anytype,
            allocator: std.mem.Allocator,
        ) !bool {
            const wants = try handler.jsonize(expected, allocator);
            const got = try handler.jsonize(actual, allocator);
            // This is a really roundabout way of doing things, but it might be
            // the easiest way to compare arbitrary zig-varlink types. Hashmap
            // ordering is not guaranteed, but it might work just well enough.
            const expected_json = try std.json.stringifyAlloc(allocator, wants, .{});
            const actual_json = try std.json.stringifyAlloc(allocator, got, .{});
            if (!std.mem.eql(u8, expected_json, actual_json)) {
                try handler.serializeResponse(
                    response_stream,
                    orgVarlinkCertification.CertificationError{
                        .wants = wants,
                        .got = got,
                    },
                    allocator,
                );
                return false;
            }
            return true;
        }

        fn checkMethod(
            context: @This(),
            method: Method,
            response_stream: anytype,
            allocator: std.mem.Allocator,
        ) !bool {
            if (context.next_method != method) {
                const wants = try std.fmt.allocPrint(
                    allocator,
                    "Call to method org.varlink.certification.{s}",
                    .{@tagName(context.next_method)},
                );
                const got = try std.fmt.allocPrint(
                    allocator,
                    "Call to method org.varlink.certification.{s}",
                    .{@tagName(method)},
                );
                try handler.serializeResponse(
                    response_stream,
                    orgVarlinkCertification.CertificationError{
                        .wants = .{ .string = wants },
                        .got = .{ .string = got },
                    },
                    allocator,
                );
                return false;
            }
            return true;
        }

        fn checkOptions(
            expected: handler.Options,
            actual: handler.Options,
            response_stream: anytype,
            allocator: std.mem.Allocator,
        ) !bool {
            if (!std.meta.eql(expected, actual)) {
                const OptionReport = struct { options: handler.Options };
                const wants: OptionReport = .{ .options = expected };
                const got: OptionReport = .{ .options = actual };
                try handler.serializeResponse(
                    response_stream,
                    orgVarlinkCertification.CertificationError{
                        .wants = try handler.jsonize(wants, allocator),
                        .got = try handler.jsonize(got, allocator),
                    },
                    allocator,
                );
                return false;
            }
            return true;
        }

        fn RequestInfo(comptime method: Method) type {
            return struct {
                parameters: @field(
                    orgVarlinkCertification,
                    @tagName(method),
                ).Parameters,
                options: handler.Options,
            };
        }

        fn checkRequest(
            context: @This(),
            comptime method: Method,
            expected: RequestInfo(method),
            actual: RequestInfo(method),
            response_stream: anytype,
            allocator: std.mem.Allocator,
        ) !bool {
            if (!try checkMethod(
                context,
                method,
                response_stream,
                allocator,
            )) {
                return false;
            }
            if (!try checkParameters(
                expected.parameters,
                actual.parameters,
                response_stream,
                allocator,
            )) {
                return false;
            }
            if (!try checkOptions(
                expected.options,
                actual.options,
                response_stream,
                allocator,
            )) {
                return false;
            }
            return true;
        }

        pub fn handleStart(
            context: *@This(),
            parameters: orgVarlinkCertification.Start.Parameters,
            response_stream: anytype,
            allocator: std.mem.Allocator,
            options: handler.Options,
            client_id: []const u8,
        ) !void {
            _ = parameters;
            context.next_method = .Test01;
            if (options.oneway) {
                return;
            }
            try handler.serializeResponse(
                response_stream,
                orgVarlinkCertification.Start.ReturnType{ .client_id = client_id },
                allocator,
            );
        }

        pub fn handleTest01(
            context: *@This(),
            parameters: orgVarlinkCertification.Test01.Parameters,
            response_stream: anytype,
            allocator: std.mem.Allocator,
            options: handler.Options,
            client_id: []const u8,
        ) !void {
            if (!try context.checkRequest(
                .Test01,
                .{
                    .parameters = .{ .client_id = client_id },
                    .options = .{},
                },
                .{
                    .parameters = parameters,
                    .options = options,
                },
                response_stream,
                allocator,
            )) {
                return;
            }
            context.next_method = .Test02;
            if (options.oneway) {
                return;
            }
            try handler.serializeResponse(
                response_stream,
                orgVarlinkCertification.Test01.ReturnType{ .bool = true },
                allocator,
            );
        }

        pub fn handleTest02(
            context: *@This(),
            parameters: orgVarlinkCertification.Test02.Parameters,
            response_stream: anytype,
            allocator: std.mem.Allocator,
            options: handler.Options,
            client_id: []const u8,
        ) !void {
            if (!try context.checkRequest(
                .Test02,
                .{
                    .parameters = .{ .client_id = client_id, .bool = true },
                    .options = .{},
                },
                .{
                    .parameters = parameters,
                    .options = options,
                },
                response_stream,
                allocator,
            )) {
                return;
            }
            context.next_method = .Test03;
            if (options.oneway) {
                return;
            }
            try handler.serializeResponse(
                response_stream,
                orgVarlinkCertification.Test02.ReturnType{ .int = 1 },
                allocator,
            );
        }

        pub fn handleTest03(
            context: *@This(),
            parameters: orgVarlinkCertification.Test03.Parameters,
            response_stream: anytype,
            allocator: std.mem.Allocator,
            options: handler.Options,
            client_id: []const u8,
        ) !void {
            if (!try context.checkRequest(
                .Test03,
                .{
                    .parameters = .{ .client_id = client_id, .int = 1 },
                    .options = .{},
                },
                .{
                    .parameters = parameters,
                    .options = options,
                },
                response_stream,
                allocator,
            )) {
                return;
            }
            context.next_method = .Test04;
            if (options.oneway) {
                return;
            }
            try handler.serializeResponse(
                response_stream,
                orgVarlinkCertification.Test03.ReturnType{ .float = 1.0 },
                allocator,
            );
        }

        pub fn handleTest04(
            context: *@This(),
            parameters: orgVarlinkCertification.Test04.Parameters,
            response_stream: anytype,
            allocator: std.mem.Allocator,
            options: handler.Options,
            client_id: []const u8,
        ) !void {
            if (!try context.checkRequest(
                .Test04,
                .{
                    .parameters = .{ .client_id = client_id, .float = 1.0 },
                    .options = .{},
                },
                .{
                    .parameters = parameters,
                    .options = options,
                },
                response_stream,
                allocator,
            )) {
                return;
            }
            context.next_method = .Test05;
            if (options.oneway) {
                return;
            }
            try handler.serializeResponse(
                response_stream,
                orgVarlinkCertification.Test04.ReturnType{ .string = "ping" },
                allocator,
            );
        }

        pub fn handleTest05(
            context: *@This(),
            parameters: orgVarlinkCertification.Test05.Parameters,
            response_stream: anytype,
            allocator: std.mem.Allocator,
            options: handler.Options,
            client_id: []const u8,
        ) !void {
            if (!try context.checkRequest(
                .Test05,
                .{
                    .parameters = .{ .client_id = client_id, .string = "ping" },
                    .options = .{},
                },
                .{
                    .parameters = parameters,
                    .options = options,
                },
                response_stream,
                allocator,
            )) {
                return;
            }
            context.next_method = .Test06;
            if (options.oneway) {
                return;
            }
            try handler.serializeResponse(
                response_stream,
                orgVarlinkCertification.Test05.ReturnType{
                    .bool = false,
                    .int = 2,
                    .float = std.math.pi,
                    .string = "a lot of string",
                },
                allocator,
            );
        }

        pub fn handleTest06(
            context: *@This(),
            parameters: orgVarlinkCertification.Test06.Parameters,
            response_stream: anytype,
            allocator: std.mem.Allocator,
            options: handler.Options,
            client_id: []const u8,
        ) !void {
            if (!try context.checkRequest(
                .Test06,
                .{
                    .parameters = .{
                        .client_id = client_id,
                        .bool = false,
                        .int = 2,
                        .float = std.math.pi,
                        .string = "a lot of string",
                    },
                    .options = .{},
                },
                .{
                    .parameters = parameters,
                    .options = options,
                },
                response_stream,
                allocator,
            )) {
                return;
            }
            context.next_method = .Test07;
            if (options.oneway) {
                return;
            }
            try handler.serializeResponse(
                response_stream,
                orgVarlinkCertification.Test06.ReturnType{
                    .@"struct" = .{
                        .bool = false,
                        .int = 2,
                        .float = std.math.pi,
                        .string = "a lot of string",
                    },
                },
                allocator,
            );
        }

        pub fn handleTest07(
            context: *@This(),
            parameters: orgVarlinkCertification.Test07.Parameters,
            response_stream: anytype,
            allocator: std.mem.Allocator,
            options: handler.Options,
            client_id: []const u8,
        ) !void {
            if (!try context.checkRequest(
                .Test07,
                .{
                    .parameters = .{
                        .client_id = client_id,
                        .@"struct" = .{
                            .bool = false,
                            .int = 2,
                            .float = std.math.pi,
                            .string = "a lot of string",
                        },
                    },
                    .options = .{},
                },
                .{
                    .parameters = parameters,
                    .options = options,
                },
                response_stream,
                allocator,
            )) {
                return;
            }
            context.next_method = .Test08;
            if (options.oneway) {
                return;
            }
            var response_map: std.StringHashMapUnmanaged([]const u8) = .{};
            try response_map.putNoClobber(allocator, "foo", "Foo");
            try response_map.putNoClobber(allocator, "bar", "Bar");
            try handler.serializeResponse(
                response_stream,
                orgVarlinkCertification.Test07.ReturnType{
                    .map = response_map,
                },
                allocator,
            );
        }

        pub fn handleTest08(
            context: *@This(),
            parameters: orgVarlinkCertification.Test08.Parameters,
            response_stream: anytype,
            allocator: std.mem.Allocator,
            options: handler.Options,
            client_id: []const u8,
        ) !void {
            var expected: std.StringHashMapUnmanaged([]const u8) = .{};
            try expected.putNoClobber(allocator, "foo", "Foo");
            try expected.putNoClobber(allocator, "bar", "Bar");
            if (!try context.checkRequest(
                .Test08,
                .{
                    .parameters = .{
                        .client_id = client_id,
                        .map = expected,
                    },
                    .options = .{},
                },
                .{
                    .parameters = parameters,
                    .options = options,
                },
                response_stream,
                allocator,
            )) {
                return;
            }
            context.next_method = .Test09;
            if (options.oneway) {
                return;
            }
            const Set = std.meta.fieldInfo(orgVarlinkCertification.Test08.ReturnType, .set).type;
            var response_set: Set = .{};
            try response_set.putNoClobber(allocator, "one", .{});
            try response_set.putNoClobber(allocator, "two", .{});
            try response_set.putNoClobber(allocator, "three", .{});
            try handler.serializeResponse(
                response_stream,
                orgVarlinkCertification.Test08.ReturnType{
                    .set = response_set,
                },
                allocator,
            );
        }

        fn generateMytype(
            allocator: std.mem.Allocator,
        ) !orgVarlinkCertification.MyType {
            const object = try handler.jsonize(
                .{
                    .method = "org.varlink.certification.Test09",
                    .parameters = .{
                        .map = .{
                            .foo = "Foo",
                            .bar = "Bar",
                        },
                    },
                },
                allocator,
            );

            const Dictionary = std.meta.fieldInfo(orgVarlinkCertification.MyType, .dictionary).type;
            var dictionary: Dictionary = .{};
            try dictionary.putNoClobber(allocator, "foo", "Foo");
            try dictionary.putNoClobber(allocator, "bar", "Bar");

            const StringSet = std.meta.fieldInfo(orgVarlinkCertification.MyType, .stringset).type;
            var stringset: StringSet = .{};
            try stringset.putNoClobber(allocator, "one", .{});
            try stringset.putNoClobber(allocator, "two", .{});
            try stringset.putNoClobber(allocator, "three", .{});

            const FooMap = std.meta.Child(
                std.meta.Child(
                    std.meta.Child(
                        std.meta.fieldInfo(orgVarlinkCertification.Interface, .foo).type,
                    ),
                ),
            );
            var map1: FooMap = .{};
            try map1.putNoClobber(allocator, "foo", .foo);
            try map1.putNoClobber(allocator, "bar", .bar);
            var map2: FooMap = .{};
            try map2.putNoClobber(allocator, "one", .foo);
            try map2.putNoClobber(allocator, "two", .bar);

            var foo_array = try allocator.alloc(?FooMap, 4);
            foo_array[0] = null;
            foo_array[1] = map1;
            foo_array[2] = null;
            foo_array[3] = map2;

            const interface_struct: orgVarlinkCertification.Interface = .{
                .foo = foo_array,
                .anon = .{
                    .foo = true,
                    .bar = false,
                },
            };

            return .{
                .object = object,
                .@"enum" = .two,
                .@"struct" = .{ .first = 1, .second = "2" },
                // Safe?
                .array = &.{ "one", "two", "three" },
                .dictionary = dictionary,
                .stringset = stringset,
                .nullable = null,
                .nullable_array_struct = null,
                .interface = interface_struct,
            };
        }

        pub fn handleTest09(
            context: *@This(),
            parameters: orgVarlinkCertification.Test09.Parameters,
            response_stream: anytype,
            allocator: std.mem.Allocator,
            options: handler.Options,
            client_id: []const u8,
        ) !void {
            const Set = std.meta.fieldInfo(orgVarlinkCertification.Test09.Parameters, .set).type;
            var expected: Set = .{};
            try expected.putNoClobber(allocator, "one", .{});
            try expected.putNoClobber(allocator, "two", .{});
            try expected.putNoClobber(allocator, "three", .{});
            if (!try context.checkRequest(
                .Test09,
                .{
                    .parameters = .{
                        .client_id = client_id,
                        .set = expected,
                    },
                    .options = .{},
                },
                .{
                    .parameters = parameters,
                    .options = options,
                },
                response_stream,
                allocator,
            )) {
                return;
            }
            context.next_method = .Test10;
            if (options.oneway) {
                return;
            }

            try handler.serializeResponse(
                response_stream,
                orgVarlinkCertification.Test09.ReturnType{
                    .mytype = try generateMytype(allocator),
                },
                allocator,
            );
        }

        pub fn handleTest10(
            context: *@This(),
            parameters: orgVarlinkCertification.Test10.Parameters,
            response_stream: anytype,
            allocator: std.mem.Allocator,
            options: handler.Options,
            client_id: []const u8,
        ) !void {
            if (!try context.checkRequest(
                .Test10,
                .{
                    .parameters = .{
                        .client_id = client_id,
                        .mytype = try generateMytype(allocator),
                    },
                    .options = .{ .more = true },
                },
                .{
                    .parameters = parameters,
                    .options = options,
                },
                response_stream,
                allocator,
            )) {
                return;
            }
            context.next_method = .Test11;
            if (options.oneway) {
                return;
            }

            var string_buf: [32]u8 = undefined;
            for (1..11) |i| {
                const string = std.fmt.bufPrint(
                    &string_buf,
                    "Reply number {}",
                    .{i},
                ) catch unreachable;
                if (i < 10) {
                    try handler.serializeContinueResponse(
                        response_stream,
                        orgVarlinkCertification.Test10.ReturnType{
                            .string = string,
                        },
                        allocator,
                    );
                    try response_stream.writeByte(0);
                } else {
                    try handler.serializeResponse(
                        response_stream,
                        orgVarlinkCertification.Test10.ReturnType{
                            .string = string,
                        },
                        allocator,
                    );
                }
            }
        }

        pub fn handleTest11(
            context: *@This(),
            parameters: orgVarlinkCertification.Test11.Parameters,
            response_stream: anytype,
            allocator: std.mem.Allocator,
            options: handler.Options,
            client_id: []const u8,
        ) !void {
            var expected_replies: [10][]const u8 = undefined;
            for (0..10) |i| {
                expected_replies[i] = try std.fmt.allocPrint(
                    allocator,
                    "Reply number {}",
                    .{i + 1},
                );
            }
            if (!try context.checkRequest(
                .Test11,
                .{
                    .parameters = .{
                        .client_id = client_id,
                        .last_more_replies = &expected_replies,
                    },
                    .options = .{ .oneway = true },
                },
                .{
                    .parameters = parameters,
                    .options = options,
                },
                response_stream,
                allocator,
            )) {
                return;
            }
            context.next_method = .End;
        }

        pub fn handleEnd(
            context: *@This(),
            parameters: orgVarlinkCertification.End.Parameters,
            response_stream: anytype,
            allocator: std.mem.Allocator,
            options: handler.Options,
            client_id: []const u8,
        ) !void {
            if (!try context.checkRequest(
                .End,
                .{
                    .parameters = .{ .client_id = client_id },
                    .options = .{},
                },
                .{
                    .parameters = parameters,
                    .options = options,
                },
                response_stream,
                allocator,
            )) {
                return;
            }
            context.done = true;

            try handler.serializeResponse(
                response_stream,
                orgVarlinkCertification.End.ReturnType{
                    .all_ok = true,
                },
                allocator,
            );
        }
    } = .{},
};

fn readRequest(reader: anytype, request_buffer: []u8) ![]u8 {
    var read_stream = std.io.fixedBufferStream(request_buffer);
    try reader.streamUntilDelimiter(
        read_stream.writer(),
        0,
        null,
    );
    return read_stream.getWritten();
}

fn handleRequest(stream: std.net.Stream, context: *Context, client_id: []const u8) !void {
    var read_buffer = std.io.bufferedReader(stream.reader());
    var request_buffer: [4096]u8 = undefined;
    var write_buffer: [4096]u8 = undefined;
    var write_stream = std.io.fixedBufferStream(&write_buffer);
    const request = try readRequest(read_buffer.reader(), &request_buffer);
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

const Arguments = struct {
    address: std.net.Address,

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
            return std.net.Address.resolveIp6(address[1..ipv6_end], port) catch error.InvalidAddress;
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

    fn parse(writer: anytype, args: *std.process.ArgIterator) !Arguments {
        if (!args.skip()) {
            try writer.writeAll("Missing program name as first argument!\n");
            return error.InvalidArguments;
        }
        const argument = args.next() orelse {
            return .{
                .address = std.net.Address.initIp4(
                    .{ 127, 0, 0, 1 },
                    23456,
                ),
            };
        };
        if (args.skip()) {
            try writer.writeAll("Expected at most one argument\n");
            return error.InvalidArguments;
        }
        const expected_prefix = "--varlink=";
        if (std.mem.startsWith(u8, argument, expected_prefix)) {
            const address = argument[expected_prefix.len..];
            const parsed_address = parseAddress(address) catch |err| {
                try writer.print("Failed to parse Varlink address: {}\n", .{err});
                return error.InvalidArguments;
            };
            return .{
                .address = parsed_address,
            };
        } else {
            try writer.print("Unexpected argument: {s}\n", .{argument});
            return error.InvalidArguments;
        }
    }
};

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

    var server = std.net.StreamServer.init(.{ .reuse_address = true });
    defer server.deinit();
    try server.listen(arguments.address);
    try stderr_writer.print("Listening to {}\n", .{server.listen_address});
    try stderr_buf.flush();

    const connection = try server.accept();
    defer connection.stream.close();
    var raw_client_id: [16]u8 = undefined;
    try std.os.getrandom(&raw_client_id);
    var client_id_buf: [32]u8 = undefined;
    _ = std.fmt.bufPrint(
        &client_id_buf,
        "{}",
        .{std.fmt.fmtSliceHexLower(&raw_client_id)},
    ) catch unreachable;
    var context: Context = .{};
    while (!context.@"org.varlink.certification".done) {
        try handleRequest(connection.stream, &context, &client_id_buf);
    }
}

test {
    _ = Arguments;
}
