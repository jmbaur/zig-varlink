// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

//! Implementation of a Varlink server

const std = @import("std");
const router = @import("router.zig");
const varlinkJson = @import("json.zig");
const Options = router.Options;
const orgVarlinkService = @import("orgVarlinkService");

/// Serialize a Varlink response or error to the given writer. A trailing zero
/// byte is not written to allow usage with transports not using one. This
/// method does not free its allocated memory, so it's recommended to use it
/// with an arena allocator
pub fn serializeResponse(
    stream: anytype,
    response: anytype,
    allocator: std.mem.Allocator,
) !void {
    const ValueType = if (@hasDecl(@TypeOf(response), "error_name")) blk: {
        break :blk struct {
            parameters: @TypeOf(response),
            @"error": []const u8 = @TypeOf(response).error_name,
        };
    } else blk: {
        break :blk struct {
            parameters: @TypeOf(response),
        };
    };

    // TODO: Have a non-allocating implementation
    try varlinkJson.write(
        stream,
        try varlinkJson.jsonize(
            ValueType{
                .parameters = response,
            },
            allocator,
        ),
    );
}

/// Serialize a Varlink response to the given writer with the "continues" flag
/// set. A trailing zero byte is not written to allow usage with transports not
/// using one. This method does not free its allocated memory, so it's
/// recommended to use it with an arena allocator
pub fn serializeContinueResponse(
    stream: anytype,
    response: anytype,
    allocator: std.mem.Allocator,
) !void {
    try varlinkJson.write(
        stream,
        try varlinkJson.jsonize(
            .{
                .parameters = response,
                .continues = true,
            },
            allocator,
        ),
    );
}

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
    response_stream: anytype,
    allocator: std.mem.Allocator,
    err: router.RouteError,
    error_info: ?[]const u8,
) !void {
    switch (err) {
        error.InvalidParameter => try serializeResponse(
            response_stream,
            orgVarlinkService.InvalidParameter{ .parameter = error_info.? },
            allocator,
        ),
        error.MethodNotImplemented => try serializeResponse(
            response_stream,
            orgVarlinkService.MethodNotImplemented{ .method = error_info.? },
            allocator,
        ),
        error.MethodNotFound => try serializeResponse(
            response_stream,
            orgVarlinkService.MethodNotFound{ .method = error_info.? },
            allocator,
        ),
        else => return err,
    }
}

/// Handle a Varlink request.
pub fn handleRequest(
    /// The request string without the trailing zero byte
    request: []const u8,
    /// The writer to which the potential response and errors will be written
    response_stream: anytype,
    /// The allocator to be used by the implementation. All allocations are
    /// always freed before the function returns.
    allocator: std.mem.Allocator,
    /// The context struct that contains request handlers
    context: anytype,
    /// Extra data to give to the request handler
    extra_data: anytype,
) !void {
    const VarlinkService = OrgVarlinkServiceImpl(@TypeOf(context.*));

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
        return serializeResponse(
        response_stream,
        orgVarlinkService.InvalidParameter{ .parameter = qualified_method },
        allocator,
    );

    const parameters = try varlinkJson.parseParameters(json_object);
    const options = try parseOptions(json_object);
    var error_info: ?[]const u8 = null;
    router.routeInterface(
        .server,
        split_method.interface,
        split_method.name,
        .{ .object = parameters },
        response_stream,
        arena.allocator(),
        options,
        context,
        extra_data,
        &error_info,
    ) catch |err| switch (err) {
        error.InvalidParameter,
        error.MethodNotImplemented,
        error.MethodNotFound,
        => try handleRouteError(
            response_stream,
            allocator,
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
                    response_stream,
                    arena.allocator(),
                    options,
                    &varlink_service_context,
                    {},
                    &error_info,
                ) catch |err2| try handleRouteError(
                    response_stream,
                    allocator,
                    err2,
                    error_info,
                );
                return;
            }
            try serializeResponse(
                response_stream,
                orgVarlinkService.InterfaceNotFound{ .interface = split_method.interface },
                allocator,
            );
        },
        else => return err,
    };
}

fn OrgVarlinkServiceImpl(comptime Context: type) type {
    return struct {
        pub const interface = orgVarlinkService;

        pub fn handleGetInfo(
            context: *@This(),
            parameters: orgVarlinkService.GetInfo.Parameters,
            response_stream: anytype,
            allocator: std.mem.Allocator,
            options: Options,
            extra_data: void,
        ) !void {
            _ = context;
            _ = parameters;
            _ = extra_data;
            if (options.oneway) {
                return;
            }
            try serializeResponse(
                response_stream,
                orgVarlinkService.GetInfo.ReturnType{
                    .vendor = Context.vendor,
                    .product = Context.product,
                    .version = Context.version,
                    .url = Context.url,
                    .interfaces = .{"org.varlink.service"} ++ std.meta.fieldNames(Context),
                },
                allocator,
            );
        }

        pub fn handleGetInterfaceDescription(
            context: *@This(),
            parameters: orgVarlinkService.GetInterfaceDescription.Parameters,
            response_stream: anytype,
            allocator: std.mem.Allocator,
            options: Options,
            extra_data: void,
        ) !void {
            _ = context;
            _ = extra_data;
            if (options.oneway) {
                return;
            }
            inline for (@typeInfo(Context).Struct.fields) |field| {
                if (std.mem.eql(u8, parameters.interface, field.name)) {
                    try serializeResponse(
                        response_stream,
                        orgVarlinkService.GetInterfaceDescription.ReturnType{
                            .description = field.type.interface.description,
                        },
                        allocator,
                    );
                    return;
                }
            }
            if (std.mem.eql(u8, "org.varlink.service", parameters.interface)) {
                try serializeResponse(
                    response_stream,
                    orgVarlinkService.GetInterfaceDescription.ReturnType{
                        .description = orgVarlinkService.description,
                    },
                    allocator,
                );
                return;
            }
            try serializeResponse(
                response_stream,
                orgVarlinkService.InterfaceNotFound{ .interface = parameters.interface },
                allocator,
            );
        }
    };
}
