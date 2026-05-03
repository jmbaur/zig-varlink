// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

const std = @import("std");

/// A Varlink address.
pub const Address = union(enum) {
    tcp: std.Io.net.IpAddress,
    unix: if (std.Io.net.has_unix_sockets) std.Io.net.UnixAddress else void,
    /// A device node.
    device: []const u8,

    /// Format the address into its string form.
    pub fn format(
        self: Address,
        writer: *std.Io.Writer,
    ) !void {
        try writer.writeAll(@tagName(self));
        try writer.writeByte(':');
        switch (self) {
            .tcp => |addr| try addr.format(writer),
            .unix => |addr| try writer.writeAll(std.mem.sliceTo(&addr.path, 0)),
            .device => |dev| try writer.writeAll(dev),
        }
    }

    pub const ParseError = std.Io.net.IpAddress.ParseLiteralError || error{
        MissingAddress,
        NameTooLong,
        NullByteInUnixPath,
        UnsupportedUnixSocket,
        UnknownScheme,
        MissingColon,
    };

    /// Parse a Varlink address string into an address. Device node paths are
    /// not copied.
    pub fn parse(address: []const u8) ParseError!Address {
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
                return .{ .tcp = try std.Io.net.IpAddress.parseLiteral(effective_address[colon_position + 1 ..]) };
            } else if (std.mem.eql(u8, "unix", scheme)) {
                if (comptime std.Io.net.has_unix_sockets) {
                    // TODO: Support Linux abstract sockets?
                    // Address.initUnix doesn't check for null bytes despite not
                    // supporting them, so let's do that ourselves.
                    if (std.mem.indexOfScalar(u8, effective_address, 0) != null) {
                        return error.NullByteInUnixPath;
                    }
                    const addr = try std.Io.net.UnixAddress.init(effective_address[colon_position + 1 ..]);
                    return .{ .unix = addr };
                } else {
                    return error.UnsupportedUnixSocket;
                }
            } else if (std.mem.eql(u8, "device", scheme)) {
                return .{ .device = effective_address[colon_position + 1 ..] };
            } else {
                return error.UnknownScheme;
            }
        } else {
            return error.MissingColon;
        }
    }

    test parse {
        {
            const address = "tcp:127.0.0.1:1234;options=123";
            const parsed = try parse(address);
            const string_form = try std.fmt.allocPrint(
                std.testing.allocator,
                "{f}",
                .{parsed},
            );
            defer std.testing.allocator.free(string_form);
            try std.testing.expectEqualStrings("tcp:127.0.0.1:1234", string_form);
        }
        {
            const address = "unix:/run/user/0/sock;options=123";
            const parsed = try parse(address);
            const string_form = try std.fmt.allocPrint(
                std.testing.allocator,
                "{f}",
                .{parsed},
            );
            defer std.testing.allocator.free(string_form);
            try std.testing.expectEqualStrings("unix:/run/user/0/sock", string_form);
        }
        {
            const address = "device:/dev/null;options=123";
            const parsed = try parse(address);
            const string_form = try std.fmt.allocPrint(
                std.testing.allocator,
                "{f}",
                .{parsed},
            );
            defer std.testing.allocator.free(string_form);
            try std.testing.expectEqualStrings("device:/dev/null", string_form);
        }
    }

    test "parse reports errors correctly" {
        {
            const address = "tcp";
            try std.testing.expectError(error.MissingColon, parse(address));
        }
        {
            const address = "tcp:";
            try std.testing.expectError(error.MissingAddress, parse(address));
        }
        {
            const address = "unix:" ++ "\x00";
            try std.testing.expectError(error.NullByteInUnixPath, parse(address));
        }
        {
            const address = "udp:127.0.0.1:0";
            try std.testing.expectError(error.UnknownScheme, parse(address));
        }
    }
};
