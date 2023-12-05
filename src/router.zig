// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

const std = @import("std");
const varlinkJson = @import("json.zig");

pub const Options = packed struct {
    oneway: bool = false,
    more: bool = false,
    upgrade: bool = false,
};

pub const RouteError = error{
    InvalidParameter,
    MethodNotImplemented,
    MethodNotFound,
    InterfaceNotFound,
} || anyerror;

const Mode = enum {
    client_method,
    client_error,
    server,
};

pub fn route(
    comptime mode: Mode,
    method: []const u8,
    parameters: std.json.Value,
    response_stream: anytype,
    allocator: std.mem.Allocator,
    options: if (mode == .server) Options else void,
    interface_context: anytype,
    extra_data: anytype,
    error_info: *?[]const u8,
) RouteError!void {
    const Interface = @TypeOf(interface_context.*).interface;
    inline for (@typeInfo(Interface).Struct.decls) |decl| {
        const Request = @field(Interface, decl.name);
        if (@typeInfo(@TypeOf(Request)) != .Type) {
            continue;
        }
        if (@hasDecl(Request, "Parameters") != (mode != .client_error)) {
            continue;
        }
        const WantedType = switch (mode) {
            .client_error => Request,
            .client_method => Request.ReturnType,
            .server => Request.Parameters,
        };
        if (std.mem.eql(u8, decl.name, method)) {
            var invalid_parameter: ?[]const u8 = null;
            const input = varlinkJson.toStruct(
                WantedType,
                allocator,
                parameters,
                &invalid_parameter,
            ) catch |err| switch (err) {
                error.InvalidParameter => {
                    error_info.* = try allocator.dupe(u8, invalid_parameter.?);
                    return error.InvalidParameter;
                },
                else => return err,
            };
            const request_function = "handle" ++ decl.name;
            if (@hasDecl(@TypeOf(interface_context.*), request_function)) {
                const function = @field(
                    @TypeOf(interface_context.*),
                    request_function,
                );
                if (comptime mode == .server) {
                    return @call(.auto, function, .{
                        interface_context,
                        input,
                        response_stream,
                        allocator,
                        options,
                        extra_data,
                    });
                } else {
                    return @call(.auto, function, .{
                        interface_context,
                        input,
                        allocator,
                        extra_data,
                    });
                }
            } else {
                error_info.* = method;
                return error.MethodNotImplemented;
            }
        }
    }
    error_info.* = method;
    return error.MethodNotFound;
}

const SeparatedName = struct {
    interface: []const u8,
    name: []const u8,
};

pub fn splitQualified(qualified_name: []const u8) ?SeparatedName {
    const last_dot = std.mem.lastIndexOfScalar(u8, qualified_name, '.') orelse
        return null;
    return .{
        .interface = qualified_name[0..last_dot],
        .name = qualified_name[last_dot + 1 ..],
    };
}

pub fn routeInterface(
    comptime mode: Mode,
    interface: []const u8,
    name: []const u8,
    parameters: std.json.Value,
    response_stream: anytype,
    allocator: std.mem.Allocator,
    options: if (mode == .server) Options else void,
    context: anytype,
    extra_data: anytype,
    error_info: *?[]const u8,
) RouteError!void {
    inline for (@typeInfo(@TypeOf(context.*)).Struct.fields) |interface_context| {
        if (std.mem.eql(u8, interface_context.name, interface)) {
            try route(
                mode,
                name,
                parameters,
                response_stream,
                allocator,
                options,
                &@field(context, interface_context.name),
                extra_data,
                error_info,
            );
            return;
        }
    }
    error_info.* = interface;
    return error.InterfaceNotFound;
}
