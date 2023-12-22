// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

//! Implementation of a Varlink server

const std = @import("std");
const router = @import("router.zig");
const varlinkJson = @import("json.zig");
const Options = router.Options;
const orgVarlinkService = @import("orgVarlinkService");

fn parseMethod(map: std.json.ObjectMap) error{InvalidMessage}![]const u8 {
    if (map.get("method")) |method_value| {
        switch (method_value) {
            .string => |method_string| return method_string,
            else => return error.InvalidMessage,
        }
    }
    return error.InvalidMessage;
}

fn readOptionValue(json: std.json.Value) error{InvalidMessage}!bool {
    switch (json) {
        .bool => |b| return b,
        .null => return false,
        else => return error.InvalidMessage,
    }
}

fn parseOptions(map: std.json.ObjectMap) error{InvalidMessage}!Options {
    var options: Options = .{};
    if (map.get("oneway")) |oneway_value| {
        options.oneway = try readOptionValue(oneway_value);
    }
    if (map.get("more")) |more_value| {
        options.more = try readOptionValue(more_value);
    }
    if (map.get("upgrade")) |upgrade_value| {
        options.upgrade = try readOptionValue(upgrade_value);
    }
    return options;
}

fn handleRouteError(
    connection: anytype,
    allocator: std.mem.Allocator,
    err: router.RouteError,
    error_info: ?[]const u8,
) !void {
    switch (err) {
        error.InvalidParameter => try connection.serializeError(
            orgVarlinkService.InvalidParameter{ .parameter = error_info.? },
            allocator,
        ),
        error.MethodNotImplemented => try connection.serializeError(
            orgVarlinkService.MethodNotImplemented{ .method = error_info.? },
            allocator,
        ),
        error.MethodNotFound => try connection.serializeError(
            orgVarlinkService.MethodNotFound{ .method = error_info.? },
            allocator,
        ),
        else => return err,
    }
}

fn ContinuationContextFor(
    comptime Conn: type,
    comptime Request: type,
) type {
    return struct {
        /// Whether the request has been responded to (without "continues" set)
        /// or not.
        finished: bool = false,
        connection: *Conn,

        /// Serialize a Varlink response to the connection.
        pub fn serializeResponse(
            continuation_context: *@This(),
            response: Request.ReturnType,
            allocator: std.mem.Allocator,
        ) !void {
            if (continuation_context.finished) {
                @panic("the request has already been responded to");
            }
            continuation_context.finished = true;
            try continuation_context.connection.response_writer.writeJson(
                try varlinkJson.jsonize(
                    .{
                        .parameters = response,
                    },
                    allocator,
                ),
            );
        }

        /// Serialize a Varlink response to the connection with "continues"
        /// enabled.
        pub fn serializeContinueResponse(
            continuation_context: @This(),
            response: Request.ReturnType,
            allocator: std.mem.Allocator,
        ) !void {
            if (continuation_context.finished) {
                @panic("the request has already been responded to");
            }
            try continuation_context.connection.response_writer.writeJson(
                try varlinkJson.jsonize(
                    .{
                        .parameters = response,
                        .continues = true,
                    },
                    allocator,
                ),
            );
        }

        /// Serialize a Varlink error to the connection.
        pub fn serializeError(
            continuation_context: @This(),
            response: anytype,
            allocator: std.mem.Allocator,
        ) !void {
            return continuation_context.connection.serializeError(
                response,
                allocator,
            );
        }
    };
}

/// Per-connection and per-request context that is passed to request handlers.
pub fn RequestContext(
    comptime Conn: type,
    comptime Request: type,
) type {
    return struct {
        pub const ContinuationContext = ContinuationContextFor(Conn, Request);

        allocator: std.mem.Allocator,
        /// The request options.
        options: Options,
        /// A version of the request context with no allocator and options. This
        /// can be used to send further responses to a client requesting them.
        /// Its methods must be used with an arena allocator or similar as they
        /// don't provide a way to free memory.
        continuation_context: ContinuationContext,

        /// Return the connection of the request context.
        pub fn getConnection(request_context: @This()) *Conn {
            return request_context.continuation_context.connection;
        }

        /// Return the user data of the connection.
        pub fn getData(request_context: @This()) std.meta.fieldInfo(Conn, .data).type {
            return request_context.continuation_context.connection.data;
        }

        /// Serialize a Varlink response to the connection.
        pub fn serializeResponse(
            request_context: *@This(),
            response: Request.ReturnType,
        ) !void {
            if (request_context.options.oneway) {
                return;
            }
            try request_context.continuation_context.serializeResponse(
                response,
                request_context.allocator,
            );
        }

        /// Serialize a Varlink response to the connection with "continues"
        /// enabled. Returns the continuation context on success and null for
        /// oneway requests.
        pub fn serializeContinueResponse(
            request_context: *@This(),
            response: Request.ReturnType,
        ) !?ContinuationContext {
            if (!request_context.options.more) {
                @panic("serializeContinueResponse called without \"more\" flag set");
            }
            if (request_context.options.oneway) {
                return null;
            }
            try request_context.continuation_context.serializeContinueResponse(
                response,
                request_context.allocator,
            );
            return request_context.continuation_context;
        }

        /// Serialize a Varlink error to the connection.
        pub fn serializeError(
            request_context: @This(),
            response: anytype,
        ) !void {
            try request_context.continuation_context.serializeError(
                response,
                request_context.allocator,
            );
        }
    };
}

/// A Varlink connection. One of these structs should exist for each connected
/// client.
pub fn Connection(
    comptime Context: type,
    comptime JsonWriter: type,
    comptime UserData: type,
) type {
    varlinkJson.checkJsonWriter(JsonWriter);
    return struct {
        /// The writer to which the potential response and errors will be written.
        response_writer: JsonWriter,
        /// Per-connection data that is available to request handlers.
        data: UserData,

        /// Handle a Varlink request.
        pub fn handleRequest(
            connection: *@This(),
            /// The request string without a trailing zero byte
            request: []const u8,
            /// The allocator to be used by the implementation. All allocations are
            /// always freed before the function returns.
            allocator: std.mem.Allocator,
            /// The context struct that contains request handlers
            context: *Context,
        ) !void {
            const VarlinkService = OrgVarlinkServiceImpl(Context);

            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const json_value = try std.json.parseFromSliceLeaky(
                std.json.Value,
                arena.allocator(),
                request,
                .{},
            );
            const json_object = switch (json_value) {
                .object => |object| object,
                else => return error.InvalidMessage,
            };

            const qualified_method = try parseMethod(json_object);
            const split_method = router.splitQualified(qualified_method) orelse
                return connection.serializeError(
                orgVarlinkService.InvalidParameter{ .parameter = qualified_method },
                arena.allocator(),
            );

            const parameters = try varlinkJson.parseParameters(json_object);
            const options = try parseOptions(json_object);
            var error_info: ?[]const u8 = null;
            router.routeInterface(
                .server,
                split_method.interface,
                split_method.name,
                .{ .object = parameters },
                arena.allocator(),
                options,
                context,
                connection,
                &error_info,
            ) catch |err| switch (err) {
                error.InvalidParameter,
                error.MethodNotImplemented,
                error.MethodNotFound,
                => try handleRouteError(
                    connection,
                    arena.allocator(),
                    err,
                    error_info,
                ),
                error.InterfaceNotFound => {
                    if (std.mem.eql(u8, "org.varlink.service", split_method.interface)) {
                        var varlink_service_context: VarlinkService = .{};
                        router.route(
                            .server,
                            split_method.name,
                            .{ .object = parameters },
                            arena.allocator(),
                            options,
                            &varlink_service_context,
                            connection,
                            &error_info,
                        ) catch |err2| try handleRouteError(
                            connection,
                            arena.allocator(),
                            err2,
                            error_info,
                        );
                        return;
                    }
                    try connection.serializeError(
                        orgVarlinkService.InterfaceNotFound{ .interface = split_method.interface },
                        arena.allocator(),
                    );
                },
                else => return err,
            };
        }

        /// Serialize a Varlink error to the given connection. This method does
        /// not free its allocated memory, so it's recommended to use it with an
        /// arena allocator
        pub fn serializeError(
            connection: *@This(),
            response: anytype,
            allocator: std.mem.Allocator,
        ) !void {
            try connection.response_writer.writeJson(
                try varlinkJson.jsonize(
                    .{
                        .parameters = response,
                        .@"error" = @TypeOf(response).error_name,
                    },
                    allocator,
                ),
            );
        }
    };
}

/// Return a new connection with the given writer and user data.
pub fn createConnection(
    comptime Context: type,
    response_writer: anytype,
    comptime T: type,
    data: T,
) Connection(
    Context,
    @TypeOf(response_writer),
    T,
) {
    return .{
        .response_writer = response_writer,
        .data = data,
    };
}

fn OrgVarlinkServiceImpl(comptime Context: type) type {
    return struct {
        pub const interface = orgVarlinkService;

        pub fn handleGetInfo(
            context: *@This(),
            parameters: orgVarlinkService.GetInfo.Parameters,
            request_context: anytype,
        ) !void {
            _ = context;
            _ = parameters;
            try request_context.serializeResponse(.{
                .vendor = Context.vendor,
                .product = Context.product,
                .version = Context.version,
                .url = Context.url,
                .interfaces = .{"org.varlink.service"} ++ std.meta.fieldNames(Context),
            });
        }

        pub fn handleGetInterfaceDescription(
            context: *@This(),
            parameters: orgVarlinkService.GetInterfaceDescription.Parameters,
            request_context: anytype,
        ) !void {
            _ = context;
            inline for (@typeInfo(Context).Struct.fields) |field| {
                if (std.mem.eql(u8, parameters.interface, field.name)) {
                    try request_context.serializeResponse(.{
                        .description = field.type.interface.description,
                    });
                    return;
                }
            }
            if (std.mem.eql(u8, "org.varlink.service", parameters.interface)) {
                try request_context.serializeResponse(.{
                    .description = orgVarlinkService.description,
                });
                return;
            }
            try request_context.serializeError(
                orgVarlinkService.InterfaceNotFound{
                    .interface = parameters.interface,
                },
            );
        }
    };
}
