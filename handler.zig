// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

//! Handler for Varlink requests

const std = @import("std");
const orgVarlinkService = @import("orgVarlinkService");

pub const Options = packed struct {
    // TODO: These are nullable in the spec, but what does a null value mean?
    oneway: bool = false,
    more: bool = false,
    upgrade: bool = false,
};

fn parseToType(
    comptime T: type,
    allocator: std.mem.Allocator,
    json: std.json.Value,
    invalid_parameter: *?[]const u8,
) (std.mem.Allocator.Error || error{InvalidParameter})!T {
    // TODO: Custom and proper implementation
    _ = invalid_parameter;
    return std.json.parseFromValueLeaky(
        T,
        allocator,
        json,
        .{ .ignore_unknown_fields = true },
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidParameter,
    };
}

/// Serialize a Varlink response or error to the given writer. A trailing zero
/// byte is not written to allow usage with transports not using one.
pub fn serializeResponse(stream: anytype, response: anytype) !void {
    // TODO: Custom and proper implementation
    const ValueType = if (@hasDecl(@TypeOf(response), "error_name"))
        struct {
            parameters: @TypeOf(response),
            @"error": []const u8 = @TypeOf(response).error_name,
        }
    else
        struct { parameters: @TypeOf(response) };

    try std.json.stringify(
        ValueType{ .parameters = response },
        .{ .emit_null_optional_fields = false },
        stream,
    );
}

fn handleMethod(
    method: []const u8,
    parameters: std.json.Value,
    response_stream: anytype,
    allocator: std.mem.Allocator,
    options: Options,
    interface_context: anytype,
    extra_data: anytype,
) !void {
    const Interface = @TypeOf(interface_context.*).interface;
    inline for (@typeInfo(Interface).Struct.decls) |decl| {
        const Request = @field(Interface, decl.name);
        if (@typeInfo(@TypeOf(Request)) != .Type) {
            continue;
        }
        if (!@hasDecl(Request, "Parameters")) {
            continue;
        }
        if (std.mem.eql(u8, decl.name, method)) {
            var invalid_parameter: ?[]const u8 = "";
            const input = parseToType(
                Request.Parameters,
                allocator,
                parameters,
                &invalid_parameter,
            ) catch |err| switch (err) {
                error.InvalidParameter => {
                    return serializeResponse(
                        response_stream,
                        orgVarlinkService.InvalidParameter{ .parameter = invalid_parameter.? },
                    );
                },
                else => return err,
            };
            const request_function = "handle" ++ decl.name;
            if (@hasDecl(@TypeOf(interface_context.*), request_function)) {
                return @call(.auto, @field(
                    @TypeOf(interface_context.*),
                    request_function,
                ), .{
                    interface_context,
                    input,
                    response_stream,
                    options,
                    extra_data,
                });
            } else {
                return serializeResponse(
                    response_stream,
                    orgVarlinkService.MethodNotImplemented{ .method = method },
                );
            }
        }
    }
    try serializeResponse(
        response_stream,
        orgVarlinkService.MethodNotFound{ .method = method },
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

fn parseOptions(map: std.json.ObjectMap) error{InvalidMessage}!Options {
    // TODO
    _ = map;
    return .{};
}

fn parseParameters(map: std.json.ObjectMap) error{InvalidMessage}!std.json.ObjectMap {
    if (map.get("parameters")) |parameters_value| {
        switch (parameters_value) {
            .object => |parameters_map| {
                return parameters_map;
            },
            else => return error.InvalidMessage,
        }
    } else {
        // libvarlink accepts lacking parameters when they are expected and
        // returns the same error as if the parameters were empty. Let's
        // match this behavior.
        return std.json.ObjectMap.init(undefined);
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
    const parameters = try parseParameters(json_object);
    const options = try parseOptions(json_object);
    const last_dot = std.mem.lastIndexOfScalar(u8, qualified_method, '.') orelse
        return serializeResponse(
        response_stream,
        orgVarlinkService.InvalidParameter{ .parameter = qualified_method },
    );
    const interface = qualified_method[0..last_dot];
    const method = qualified_method[last_dot + 1 ..];
    inline for (@typeInfo(@TypeOf(context.*)).Struct.fields) |field| {
        if (std.mem.eql(u8, field.name, interface)) {
            try handleMethod(
                method,
                .{ .object = parameters },
                response_stream,
                arena.allocator(),
                options,
                &@field(context, field.name),
                extra_data,
            );
            return;
        }
    }
    if (std.mem.eql(u8, "org.varlink.service", interface)) {
        var varlink_service_context: VarlinkService = .{};
        try handleMethod(
            method,
            .{ .object = parameters },
            response_stream,
            arena.allocator(),
            options,
            &varlink_service_context,
            {},
        );
        return;
    }
    try serializeResponse(
        response_stream,
        orgVarlinkService.InterfaceNotFound{ .interface = interface },
    );
}

fn OrgVarlinkServiceImpl(comptime Context: type) type {
    return struct {
        const interface = orgVarlinkService;

        fn handleGetInfo(
            context: *@This(),
            parameters: orgVarlinkService.GetInfo.Parameters,
            response_stream: anytype,
            options: Options,
            extra_data: void,
        ) !void {
            _ = context;
            _ = parameters;
            _ = extra_data;
            if (options.oneway) {
                return;
            }
            try serializeResponse(response_stream, orgVarlinkService.GetInfo.ReturnType{
                .vendor = Context.vendor,
                .product = Context.product,
                .version = Context.version,
                .url = Context.url,
                .interfaces = .{"org.varlink.service"} ++ std.meta.fieldNames(Context),
            });
        }

        fn handleGetInterfaceDescription(
            context: *@This(),
            parameters: orgVarlinkService.GetInterfaceDescription.Parameters,
            response_stream: anytype,
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
                );
                return;
            }
            try serializeResponse(
                response_stream,
                orgVarlinkService.InterfaceNotFound{ .interface = parameters.interface },
            );
        }
    };
}
