// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

const std = @import("std");
const server = @import("varlink-server");
const orgVarlinkCertification = @import("orgVarlinkCertification");

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
        const wants = try server.varlinkJson.jsonize(expected, allocator);
        const got = try server.varlinkJson.jsonize(actual, allocator);
        // This is a really roundabout way of doing things, but it might be
        // the easiest way to compare arbitrary zig-varlink types. Hashmap
        // ordering is not guaranteed, but it might work just well enough.
        const expected_json = try std.json.stringifyAlloc(allocator, wants, .{});
        const actual_json = try std.json.stringifyAlloc(allocator, got, .{});
        if (!std.mem.eql(u8, expected_json, actual_json)) {
            try server.serializeResponse(
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
            try server.serializeResponse(
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
        expected: server.Options,
        actual: server.Options,
        response_stream: anytype,
        allocator: std.mem.Allocator,
    ) !bool {
        if (!std.meta.eql(expected, actual)) {
            const OptionReport = struct { options: server.Options };
            const wants: OptionReport = .{ .options = expected };
            const got: OptionReport = .{ .options = actual };
            try server.serializeResponse(
                response_stream,
                orgVarlinkCertification.CertificationError{
                    .wants = try server.varlinkJson.jsonize(wants, allocator),
                    .got = try server.varlinkJson.jsonize(got, allocator),
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
            options: server.Options,
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
        options: server.Options,
        client_id: []const u8,
    ) !void {
        _ = parameters;
        context.next_method = .Test01;
        if (options.oneway) {
            return;
        }
        try server.serializeResponse(
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
        options: server.Options,
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
        try server.serializeResponse(
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
        options: server.Options,
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
        try server.serializeResponse(
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
        options: server.Options,
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
        try server.serializeResponse(
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
        options: server.Options,
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
        try server.serializeResponse(
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
        options: server.Options,
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
        try server.serializeResponse(
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
        options: server.Options,
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
        try server.serializeResponse(
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
        options: server.Options,
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
        try server.serializeResponse(
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
        options: server.Options,
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
        try server.serializeResponse(
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
        const object = try server.varlinkJson.jsonize(
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
        options: server.Options,
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

        try server.serializeResponse(
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
        options: server.Options,
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
                try server.serializeContinueResponse(
                    response_stream,
                    orgVarlinkCertification.Test10.ReturnType{
                        .string = string,
                    },
                    allocator,
                );
                try response_stream.writeByte(0);
            } else {
                try server.serializeResponse(
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
        options: server.Options,
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
        options: server.Options,
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

        try server.serializeResponse(
            response_stream,
            orgVarlinkCertification.End.ReturnType{
                .all_ok = true,
            },
            allocator,
        );
    }
} = .{},
