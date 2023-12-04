// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

const std = @import("std");
const router = @import("router");
pub const varlinkJson = router.varlinkJson;
pub const Options = router.Options;

/// Return the number of requests of the given context.
fn countRequests(comptime Context: type) comptime_int {
    var request_count: comptime_int = 0;
    for (std.meta.fields(Context)) |field| {
        const Interface = field.type.interface;
        const decls = @typeInfo(Interface).Struct.decls;
        for (decls) |decl| {
            const Decl = @field(Interface, decl.name);
            if (@typeInfo(@TypeOf(Decl)) == .Type and @hasDecl(Decl, "Parameters")) {
                request_count += 1;
            }
        }
    }
    return request_count;
}

/// Generate an enum with the Context's requests' qualified names as fields.
fn RequestEnum(comptime Context: type) type {
    const request_count = countRequests(Context);
    var requests: [request_count]std.builtin.Type.EnumField = undefined;
    var count_requests: u32 = 0;
    for (std.meta.fields(Context)) |field| {
        const Interface = field.type.interface;
        const decls = @typeInfo(Interface).Struct.decls;
        for (decls) |decl| {
            const Decl = @field(Interface, decl.name);
            if (@typeInfo(@TypeOf(Decl)) == .Type and @hasDecl(Decl, "Parameters")) {
                requests[count_requests] = .{
                    .name = field.name ++ "." ++ decl.name,
                    .value = count_requests,
                };
                count_requests += 1;
            }
        }
    }
    return @Type(.{
        .Enum = .{
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
    const Enum = RequestEnum(Context);
    return struct {
        context: *Context,
        /// The queue of requests currently waiting to get responded to.
        requests: std.fifo.LinearFifo(Enum, .Dynamic),
        /// True if multiple replies are requested with the "more" option and
        /// the server hasn't yet sent a reply without the "continues" flag set.
        more: bool = false,
        /// True if the server has sent an error. This renders this client state
        /// invalid as it makes it impossible to associate further replies with
        /// requests, so it's not allowed to serialize requests with this state
        /// if this field is set.
        errored: bool = false,

        pub fn init(context: *Context, allocator: std.mem.Allocator) @This() {
            return .{
                .context = context,
                .requests = .{
                    .allocator = allocator,
                    .buf = &.{},
                    .head = 0,
                    .count = 0,
                },
            };
        }

        pub fn deinit(client: *@This()) void {
            client.requests.deinit();
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
                // receiving an error. It's becomes impossible to know which
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
            stream: anytype,
            /// The fully qualified name of the request as an enum tag
            comptime method: Enum,
            parameters: RequestParameters(Context, method),
            options: Options,
            /// The allocator to be used. The allocated memory is not feed on
            /// success or on failure, so it's recommended to use an arena
            /// allocator.
            allocator: std.mem.Allocator,
        ) !void {
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

            client.updateFlags(options);
            try varlinkJson.write(
                stream,
                .{ .object = response_map },
            );
            if (!options.oneway) {
                try client.requests.writeItem(method);
            }
        }

        /// Handle a Varlink message from the server.
        pub fn handleResponse(
            client: *@This(),
            response: []const u8,
            /// The allocator to be used for temporary allocations. All memory
            /// allocated will be freed before this function returns.
            allocator: std.mem.Allocator,
        ) !void {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const json_value = try std.json.parseFromSliceLeaky(
                std.json.Value,
                arena.allocator(),
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
                    {},
                    arena.allocator(),
                    {},
                    client.context,
                    client,
                    &error_info,
                );
            }
            // TODO: Return error on empty fifo? The server could be sending an
            // unwarranted response at this point instead of the client code
            // being wrong.
            const qualified_method = @tagName(client.requests.peekItem(0));
            const split_method = router.splitQualified(qualified_method) orelse
                return error.InvalidMessage;

            const continues = try parseContinues(json_object);
            if (continues and !client.more) {
                return error.InvalidMessage;
            }
            if (!continues) {
                client.more = false;
                client.requests.discard(1);
            }

            // TODO: Pass this to the user?
            var error_info: ?[]const u8 = null;
            try router.routeInterface(
                .client_method,
                split_method.interface,
                split_method.name,
                .{ .object = parameters },
                {},
                arena.allocator(),
                {},
                client.context,
                client,
                &error_info,
            );
        }
    };
}
