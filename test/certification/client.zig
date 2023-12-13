// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

const std = @import("std");
const orgVarlinkCertification = @import("orgVarlinkCertification");

@"org.varlink.certification": struct {
    pub const interface = orgVarlinkCertification;

    allocator: std.mem.Allocator,
    client_id: []const u8 = "",
    last_more_replies: std.ArrayListUnmanaged([]const u8) = .{},
    done: bool = false,

    pub fn deinit(context: *@This()) void {
        context.allocator.free(context.client_id);
        context.last_more_replies.deinit(context.allocator);
    }

    pub fn handleStart(
        context: *@This(),
        response: orgVarlinkCertification.Start.ReturnType,
        allocator: std.mem.Allocator,
        state: anytype,
    ) !void {
        context.client_id = try context.allocator.dupe(u8, response.client_id);
        errdefer context.allocator.free(context.client_id);
        try state.serializeRequest(
            .@"org.varlink.certification.Test01",
            .{ .client_id = context.client_id },
            .{},
            allocator,
        );
    }

    pub fn handleTest01(
        context: *@This(),
        response: orgVarlinkCertification.Test01.ReturnType,
        allocator: std.mem.Allocator,
        state: anytype,
    ) !void {
        try state.serializeRequest(
            .@"org.varlink.certification.Test02",
            .{
                .client_id = context.client_id,
                .bool = response.bool,
            },
            .{},
            allocator,
        );
    }

    pub fn handleTest02(
        context: *@This(),
        response: orgVarlinkCertification.Test02.ReturnType,
        allocator: std.mem.Allocator,
        state: anytype,
    ) !void {
        try state.serializeRequest(
            .@"org.varlink.certification.Test03",
            .{
                .client_id = context.client_id,
                .int = response.int,
            },
            .{},
            allocator,
        );
    }

    pub fn handleTest03(
        context: *@This(),
        response: orgVarlinkCertification.Test03.ReturnType,
        allocator: std.mem.Allocator,
        state: anytype,
    ) !void {
        try state.serializeRequest(
            .@"org.varlink.certification.Test04",
            .{
                .client_id = context.client_id,
                .float = response.float,
            },
            .{},
            allocator,
        );
    }

    pub fn handleTest04(
        context: *@This(),
        response: orgVarlinkCertification.Test04.ReturnType,
        allocator: std.mem.Allocator,
        state: anytype,
    ) !void {
        try state.serializeRequest(
            .@"org.varlink.certification.Test05",
            .{
                .client_id = context.client_id,
                .string = response.string,
            },
            .{},
            allocator,
        );
    }

    pub fn handleTest05(
        context: *@This(),
        response: orgVarlinkCertification.Test05.ReturnType,
        allocator: std.mem.Allocator,
        state: anytype,
    ) !void {
        try state.serializeRequest(
            .@"org.varlink.certification.Test06",
            .{
                .client_id = context.client_id,
                .bool = response.bool,
                .int = response.int,
                .float = response.float,
                .string = response.string,
            },
            .{},
            allocator,
        );
    }

    pub fn handleTest06(
        context: *@This(),
        response: orgVarlinkCertification.Test06.ReturnType,
        allocator: std.mem.Allocator,
        state: anytype,
    ) !void {
        try state.serializeRequest(
            .@"org.varlink.certification.Test07",
            .{
                .client_id = context.client_id,
                .@"struct" = .{
                    .bool = response.@"struct".bool,
                    .int = response.@"struct".int,
                    .float = response.@"struct".float,
                    .string = response.@"struct".string,
                },
            },
            .{},
            allocator,
        );
    }

    pub fn handleTest07(
        context: *@This(),
        response: orgVarlinkCertification.Test07.ReturnType,
        allocator: std.mem.Allocator,
        state: anytype,
    ) !void {
        try state.serializeRequest(
            .@"org.varlink.certification.Test08",
            .{
                .client_id = context.client_id,
                .map = response.map,
            },
            .{},
            allocator,
        );
    }

    pub fn handleTest08(
        context: *@This(),
        response: orgVarlinkCertification.Test08.ReturnType,
        allocator: std.mem.Allocator,
        state: anytype,
    ) !void {
        // The response's .{} is not compatible with the parameters'. Let's copy
        // the set.
        var return_set: std.meta.fieldInfo(
            orgVarlinkCertification.Test09.Parameters,
            .set,
        ).type = .{};
        try return_set.ensureTotalCapacity(context.allocator, response.set.size);
        var it = response.set.keyIterator();
        while (it.next()) |key| {
            return_set.putAssumeCapacityNoClobber(key.*, .{});
        }
        try state.serializeRequest(
            .@"org.varlink.certification.Test09",
            .{
                .client_id = context.client_id,
                .set = return_set,
            },
            .{},
            allocator,
        );
    }

    pub fn handleTest09(
        context: *@This(),
        response: orgVarlinkCertification.Test09.ReturnType,
        allocator: std.mem.Allocator,
        state: anytype,
    ) !void {
        try state.serializeRequest(
            .@"org.varlink.certification.Test10",
            .{
                .client_id = context.client_id,
                .mytype = response.mytype,
            },
            .{ .more = true },
            allocator,
        );
    }

    pub fn handleTest10(
        context: *@This(),
        response: orgVarlinkCertification.Test10.ReturnType,
        allocator: std.mem.Allocator,
        state: anytype,
    ) !void {
        try context.last_more_replies.append(
            context.allocator,
            try context.allocator.dupe(u8, response.string),
        );
        if (!state.more) {
            try state.serializeRequest(
                .@"org.varlink.certification.Test11",
                .{
                    .client_id = context.client_id,
                    .last_more_replies = context.last_more_replies.items,
                },
                .{ .oneway = true },
                allocator,
            );
            try state.serializeRequest(
                .@"org.varlink.certification.End",
                .{
                    .client_id = context.client_id,
                },
                .{},
                allocator,
            );
        }
    }

    pub fn handleEnd(
        context: *@This(),
        response: orgVarlinkCertification.End.ReturnType,
        allocator: std.mem.Allocator,
        state: anytype,
    ) !void {
        _ = allocator;
        _ = state;
        if (!response.all_ok) {
            return error.CertificationFailed;
        }
        context.done = true;
    }
},
