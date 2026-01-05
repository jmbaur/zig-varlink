// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

const std = @import("std");
const router = @import("router.zig");
const varlinkJson = @import("json.zig");
const Options = router.Options;

/// Return the number of requests of the given context.
fn countRequests(comptime Context: type) comptime_int {
    var request_count: comptime_int = 0;
    for (std.meta.fields(Context)) |field| {
        const Interface = field.type.interface;
        const decls = @typeInfo(Interface).@"struct".decls;
        for (decls) |decl| {
            const Decl = @field(Interface, decl.name);
            if (@typeInfo(@TypeOf(Decl)) == .type and @hasDecl(Decl, "Parameters")) {
                request_count += 1;
            }
        }
    }
    return request_count;
}

/// Generate an enum with the Context's requests' qualified names as fields.
fn RequestEnumFor(comptime Context: type) type {
    const request_count = countRequests(Context);
    var requests: [request_count]std.builtin.Type.EnumField = undefined;
    var count_requests: u32 = 0;
    for (std.meta.fields(Context)) |field| {
        const Interface = field.type.interface;
        const decls = @typeInfo(Interface).@"struct".decls;
        for (decls) |decl| {
            const Decl = @field(Interface, decl.name);
            if (@typeInfo(@TypeOf(Decl)) == .type and @hasDecl(Decl, "Parameters")) {
                requests[count_requests] = .{
                    .name = field.name ++ "." ++ decl.name,
                    .value = count_requests,
                };
                count_requests += 1;
            }
        }
    }
    return @Type(.{
        .@"enum" = .{
            .tag_type = std.math.IntFittingRange(0, count_requests),
            .fields = requests[0..count_requests],
            .decls = &.{},
            .is_exhaustive = true,
        },
    });
}

fn FieldTypeByName(comptime T: type, comptime name: []const u8) type {
    for (std.meta.fields(T)) |field| {
        if (std.mem.eql(u8, name, field.name)) {
            return field.type;
        }
    }
    return void;
}

/// Return the parameter type for the given request.
fn RequestParameters(comptime Context: type, comptime request: anytype) type {
    const split_name = router.splitQualified(@tagName(request)).?;
    const Interface = FieldTypeByName(Context, split_name.interface).interface;
    return @field(Interface, split_name.name).Parameters;
}

/// The state of a Varlink client.
pub fn Client(comptime Context: type) type {
    return struct {
        /// An enum with all fully qualified request names from the interfaces
        /// of the Context as field names.
        pub const RequestEnum = RequestEnumFor(Context);

        context: *Context,
        /// The writer to which Varlink requests are written.
        request_writer: *std.Io.Writer,
        /// The queue of requests currently waiting to get responded to.
        requests: [std.math.maxInt(u7) + 1]RequestEnum = undefined,
        request_read_index: u7 = 0,
        request_write_index: u7 = 0,
        /// True if multiple replies are requested with the "more" option and
        /// the server hasn't yet sent a reply without the "continues" flag set.
        more: bool = false,
        /// True if the server has sent an error. This renders this client state
        /// invalid as it makes it impossible to associate further replies with
        /// requests, so it's not allowed to serialize requests with this state
        /// if this field is set.
        errored: bool = false,
        /// The arena allocator used for parsing requests and generating
        /// responses. This is reset every time handleResponse is called,
        /// invalidating all allocated parameters passed to response handlers.
        arena: std.heap.ArenaAllocator,

        const max_retained_capacity = 8192;

        pub fn init(
            context: *Context,
            request_writer: *std.Io.Writer,
            allocator: std.mem.Allocator,
        ) @This() {
            return .{
                .context = context,
                .request_writer = request_writer,
                .arena = std.heap.ArenaAllocator.init(allocator),
            };
        }

        pub fn deinit(client: *@This()) void {
            client.arena.deinit();
        }

        fn parseError(map: std.json.ObjectMap) error{InvalidMessage}!?[]const u8 {
            if (map.get("error")) |error_value| {
                switch (error_value) {
                    .string => |error_string| return error_string,
                    .null => return null,
                    else => return error.InvalidMessage,
                }
            }
            return null;
        }

        fn parseContinues(map: std.json.ObjectMap) error{InvalidMessage}!bool {
            if (map.get("continues")) |continues_value| {
                switch (continues_value) {
                    .bool => |continues_bool| return continues_bool,
                    .null => return false,
                    else => return error.InvalidMessage,
                }
            }
            return false;
        }

        fn updateFlags(client: *@This(), options: Options) void {
            if (client.errored) {
                // It's a programming error to keep doing requests after
                // receiving an error. It becomes impossible to know which
                // response relates to which request after an error has been
                // received.
                @panic("An error has been received from the server");
            }
            if (client.more) {
                @panic("The server is still sending continuation replies");
            }
            if (options.more and options.oneway) {
                @panic("More and oneway used simultaneously");
            }
            client.more = options.more;
        }

        /// Serialize a Varlink request.
        pub fn serializeRequest(
            client: *@This(),
            /// The fully qualified name of the request as an enum tag
            comptime method: RequestEnum,
            parameters: RequestParameters(Context, method),
            options: Options,
        ) !void {
            const allocator = client.arena.allocator();
            var response_map = std.json.ObjectMap.init(allocator);
            try response_map.putNoClobber("method", .{ .string = @tagName(method) });
            try response_map.putNoClobber(
                "parameters",
                try varlinkJson.jsonize(parameters, allocator),
            );
            if (options.oneway) {
                try response_map.putNoClobber("oneway", .{ .bool = true });
            }
            if (options.more) {
                try response_map.putNoClobber("more", .{ .bool = true });
            }
            if (options.upgrade) {
                try response_map.putNoClobber("upgrade", .{ .bool = true });
            }
            const json: std.json.Value = .{ .object = response_map };

            client.updateFlags(options);
            try std.json.Stringify.value(json, .{}, client.request_writer);
            try client.request_writer.writeByte(0);
            if (!options.oneway) {
                client.requests[client.request_write_index] = method;
                client.request_write_index +%= 1;
            }
        }

        /// Handle a Varlink message from the server.
        pub fn handleResponse(
            client: *@This(),
            response: []const u8,
        ) !void {
            _ = client.arena.reset(.{ .retain_with_limit = @This().max_retained_capacity });
            const allocator = client.arena.allocator();
            const json_value = try std.json.parseFromSliceLeaky(
                std.json.Value,
                allocator,
                response,
                .{},
            );
            const json_object = switch (json_value) {
                .object => |object| object,
                else => return error.InvalidMessage,
            };

            const parameters = try varlinkJson.parseParameters(json_object);

            if (try parseError(json_object)) |qualified_error| {
                client.errored = true;
                const split_error = router.splitQualified(qualified_error) orelse
                    return error.InvalidMessage;
                var error_info: ?[]const u8 = null;
                try router.routeInterface(
                    .client_error,
                    split_error.interface,
                    split_error.name,
                    .{ .object = parameters },
                    allocator,
                    {},
                    client.context,
                    client,
                    &error_info,
                );
            }
            // TODO: Return error on empty request queue? The server could be
            // sending an unwarranted response at this point instead of the
            // client code being wrong.
            const qualified_method = @tagName(client.requests[client.request_read_index]);
            const split_method = router.splitQualified(qualified_method) orelse
                return error.InvalidMessage;

            const continues = try parseContinues(json_object);
            if (continues and !client.more) {
                return error.InvalidMessage;
            }
            if (!continues) {
                client.more = false;
                client.request_read_index +%= 1;
            }

            // TODO: Pass this to the user?
            var error_info: ?[]const u8 = null;
            try router.routeInterface(
                .client_method,
                split_method.interface,
                split_method.name,
                .{ .object = parameters },
                allocator,
                {},
                client.context,
                client,
                &error_info,
            );
        }
    };
}
