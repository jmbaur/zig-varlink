// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

const std = @import("std");
const varlink = @import("varlink");
const server = varlink.server;
const Options = varlink.Options;
const json = varlink.json;
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
        connection: anytype,
        allocator: std.mem.Allocator,
    ) !bool {
        const wants = try json.jsonize(expected, allocator);
        const got = try json.jsonize(actual, allocator);
        // This is a really roundabout way of doing things, but it might be
        // the easiest way to compare arbitrary zig-varlink types. Hashmap
        // ordering is not guaranteed, but it might work just well enough.
        const expected_json = try std.json.stringifyAlloc(allocator, wants, .{});
        const actual_json = try std.json.stringifyAlloc(allocator, got, .{});
        if (!std.mem.eql(u8, expected_json, actual_json)) {
            try connection.serializeError(
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
        connection: anytype,
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
            try connection.serializeError(
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
        expected: Options,
        actual: Options,
        connection: anytype,
        allocator: std.mem.Allocator,
    ) !bool {
        if (!std.meta.eql(expected, actual)) {
            const OptionReport = struct { options: Options };
            const wants: OptionReport = .{ .options = expected };
            const got: OptionReport = .{ .options = actual };
            try connection.serializeError(
                orgVarlinkCertification.CertificationError{
                    .wants = try json.jsonize(wants, allocator),
                    .got = try json.jsonize(got, allocator),
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
            options: Options,
        };
    }

    fn checkRequest(
        context: @This(),
        comptime method: Method,
        expected: RequestInfo(method),
        actual: RequestInfo(method),
        connection: anytype,
        allocator: std.mem.Allocator,
    ) !bool {
        if (!try checkMethod(
            context,
            method,
            connection,
            allocator,
        )) {
            return false;
        }
        if (!try checkParameters(
            expected.parameters,
            actual.parameters,
            connection,
            allocator,
        )) {
            return false;
        }
        if (!try checkOptions(
            expected.options,
            actual.options,
            connection,
            allocator,
        )) {
            return false;
        }
        return true;
    }

    pub fn handleStart(
        context: *@This(),
        parameters: orgVarlinkCertification.Start.Parameters,
        request_context: anytype,
    ) !void {
        _ = parameters;
        context.next_method = .Test01;
        try request_context.serializeResponse(
            .{ .client_id = request_context.connection.data },
        );
    }

    pub fn handleTest01(
        context: *@This(),
        parameters: orgVarlinkCertification.Test01.Parameters,
        request_context: anytype,
    ) !void {
        if (!try context.checkRequest(
            .Test01,
            .{
                .parameters = .{ .client_id = request_context.connection.data },
                .options = .{},
            },
            .{
                .parameters = parameters,
                .options = request_context.options,
            },
            request_context.connection,
            request_context.allocator,
        )) {
            return;
        }
        context.next_method = .Test02;
        try request_context.serializeResponse(.{ .bool = true });
    }

    pub fn handleTest02(
        context: *@This(),
        parameters: orgVarlinkCertification.Test02.Parameters,
        request_context: anytype,
    ) !void {
        if (!try context.checkRequest(
            .Test02,
            .{
                .parameters = .{ .client_id = request_context.connection.data, .bool = true },
                .options = .{},
            },
            .{
                .parameters = parameters,
                .options = request_context.options,
            },
            request_context.connection,
            request_context.allocator,
        )) {
            return;
        }
        context.next_method = .Test03;
        try request_context.serializeResponse(.{ .int = 1 });
    }

    pub fn handleTest03(
        context: *@This(),
        parameters: orgVarlinkCertification.Test03.Parameters,
        request_context: anytype,
    ) !void {
        if (!try context.checkRequest(
            .Test03,
            .{
                .parameters = .{ .client_id = request_context.connection.data, .int = 1 },
                .options = .{},
            },
            .{
                .parameters = parameters,
                .options = request_context.options,
            },
            request_context.connection,
            request_context.allocator,
        )) {
            return;
        }
        context.next_method = .Test04;
        try request_context.serializeResponse(.{ .float = 1.0 });
    }

    pub fn handleTest04(
        context: *@This(),
        parameters: orgVarlinkCertification.Test04.Parameters,
        request_context: anytype,
    ) !void {
        if (!try context.checkRequest(
            .Test04,
            .{
                .parameters = .{ .client_id = request_context.connection.data, .float = 1.0 },
                .options = .{},
            },
            .{
                .parameters = parameters,
                .options = request_context.options,
            },
            request_context.connection,
            request_context.allocator,
        )) {
            return;
        }
        context.next_method = .Test05;
        try request_context.serializeResponse(.{ .string = "ping" });
    }

    pub fn handleTest05(
        context: *@This(),
        parameters: orgVarlinkCertification.Test05.Parameters,
        request_context: anytype,
    ) !void {
        if (!try context.checkRequest(
            .Test05,
            .{
                .parameters = .{ .client_id = request_context.connection.data, .string = "ping" },
                .options = .{},
            },
            .{
                .parameters = parameters,
                .options = request_context.options,
            },
            request_context.connection,
            request_context.allocator,
        )) {
            return;
        }
        context.next_method = .Test06;
        try request_context.serializeResponse(
            .{
                .bool = false,
                .int = 2,
                .float = std.math.pi,
                .string = "a lot of string",
            },
        );
    }

    pub fn handleTest06(
        context: *@This(),
        parameters: orgVarlinkCertification.Test06.Parameters,
        request_context: anytype,
    ) !void {
        if (!try context.checkRequest(
            .Test06,
            .{
                .parameters = .{
                    .client_id = request_context.connection.data,
                    .bool = false,
                    .int = 2,
                    .float = std.math.pi,
                    .string = "a lot of string",
                },
                .options = .{},
            },
            .{
                .parameters = parameters,
                .options = request_context.options,
            },
            request_context.connection,
            request_context.allocator,
        )) {
            return;
        }
        context.next_method = .Test07;
        try request_context.serializeResponse(
            .{
                .@"struct" = .{
                    .bool = false,
                    .int = 2,
                    .float = std.math.pi,
                    .string = "a lot of string",
                },
            },
        );
    }

    pub fn handleTest07(
        context: *@This(),
        parameters: orgVarlinkCertification.Test07.Parameters,
        request_context: anytype,
    ) !void {
        if (!try context.checkRequest(
            .Test07,
            .{
                .parameters = .{
                    .client_id = request_context.connection.data,
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
                .options = request_context.options,
            },
            request_context.connection,
            request_context.allocator,
        )) {
            return;
        }
        context.next_method = .Test08;
        var response_map: std.StringHashMapUnmanaged([]const u8) = .{};
        try response_map.putNoClobber(request_context.allocator, "foo", "Foo");
        try response_map.putNoClobber(request_context.allocator, "bar", "Bar");
        try request_context.serializeResponse(.{ .map = response_map });
    }

    pub fn handleTest08(
        context: *@This(),
        parameters: orgVarlinkCertification.Test08.Parameters,
        request_context: anytype,
    ) !void {
        var expected: std.StringHashMapUnmanaged([]const u8) = .{};
        try expected.putNoClobber(request_context.allocator, "foo", "Foo");
        try expected.putNoClobber(request_context.allocator, "bar", "Bar");
        if (!try context.checkRequest(
            .Test08,
            .{
                .parameters = .{
                    .client_id = request_context.connection.data,
                    .map = expected,
                },
                .options = .{},
            },
            .{
                .parameters = parameters,
                .options = request_context.options,
            },
            request_context.connection,
            request_context.allocator,
        )) {
            return;
        }
        context.next_method = .Test09;
        const Set = std.meta.fieldInfo(orgVarlinkCertification.Test08.ReturnType, .set).type;
        var response_set: Set = .{};
        try response_set.putNoClobber(request_context.allocator, "one", .{});
        try response_set.putNoClobber(request_context.allocator, "two", .{});
        try response_set.putNoClobber(request_context.allocator, "three", .{});
        try request_context.serializeResponse(.{ .set = response_set });
    }

    fn generateMytype(
        allocator: std.mem.Allocator,
    ) !orgVarlinkCertification.MyType {
        const object = try json.jsonize(
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
        request_context: anytype,
    ) !void {
        const Set = std.meta.fieldInfo(orgVarlinkCertification.Test09.Parameters, .set).type;
        var expected: Set = .{};
        try expected.putNoClobber(request_context.allocator, "one", .{});
        try expected.putNoClobber(request_context.allocator, "two", .{});
        try expected.putNoClobber(request_context.allocator, "three", .{});
        if (!try context.checkRequest(
            .Test09,
            .{
                .parameters = .{
                    .client_id = request_context.connection.data,
                    .set = expected,
                },
                .options = .{},
            },
            .{
                .parameters = parameters,
                .options = request_context.options,
            },
            request_context.connection,
            request_context.allocator,
        )) {
            return;
        }
        context.next_method = .Test10;

        try request_context.serializeResponse(.{
            .mytype = try generateMytype(request_context.allocator),
        });
    }

    pub fn handleTest10(
        context: *@This(),
        parameters: orgVarlinkCertification.Test10.Parameters,
        request_context: anytype,
    ) !void {
        if (!try context.checkRequest(
            .Test10,
            .{
                .parameters = .{
                    .client_id = request_context.connection.data,
                    .mytype = try generateMytype(request_context.allocator),
                },
                .options = .{ .more = true },
            },
            .{
                .parameters = parameters,
                .options = request_context.options,
            },
            request_context.connection,
            request_context.allocator,
        )) {
            return;
        }
        context.next_method = .Test11;

        var string_buf: [32]u8 = undefined;
        for (1..11) |i| {
            const string = std.fmt.bufPrint(
                &string_buf,
                "Reply number {}",
                .{i},
            ) catch unreachable;
            if (i < 10) {
                try request_context.serializeContinueResponse(.{ .string = string });
                try request_context.connection.response_stream.writeByte(0);
            } else {
                try request_context.serializeResponse(.{ .string = string });
            }
        }
    }

    pub fn handleTest11(
        context: *@This(),
        parameters: orgVarlinkCertification.Test11.Parameters,
        request_context: anytype,
    ) !void {
        var expected_replies: [10][]const u8 = undefined;
        for (0..10) |i| {
            expected_replies[i] = try std.fmt.allocPrint(
                request_context.allocator,
                "Reply number {}",
                .{i + 1},
            );
        }
        if (!try context.checkRequest(
            .Test11,
            .{
                .parameters = .{
                    .client_id = request_context.connection.data,
                    .last_more_replies = &expected_replies,
                },
                .options = .{ .oneway = true },
            },
            .{
                .parameters = parameters,
                .options = request_context.options,
            },
            request_context.connection,
            request_context.allocator,
        )) {
            return;
        }
        context.next_method = .End;
    }

    pub fn handleEnd(
        context: *@This(),
        parameters: orgVarlinkCertification.End.Parameters,
        request_context: anytype,
    ) !void {
        if (!try context.checkRequest(
            .End,
            .{
                .parameters = .{ .client_id = request_context.connection.data },
                .options = .{},
            },
            .{
                .parameters = parameters,
                .options = request_context.options,
            },
            request_context.connection,
            request_context.allocator,
        )) {
            return;
        }
        context.done = true;

        try request_context.serializeResponse(.{ .all_ok = true });
    }
} = .{},
