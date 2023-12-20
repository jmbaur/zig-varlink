// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

const std = @import("std");

pub const TcpAddress = union(enum) {
    ipv4: std.net.Ip4Address,
    ipv6: std.net.Ip6Address,

    pub fn format(
        self: TcpAddress,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        switch (self) {
            inline else => |addr| try addr.format(fmt, options, out_stream),
        }
    }

    pub fn toNetAddress(address: TcpAddress) std.net.Address {
        return switch (address) {
            .ipv4 => |addr| .{ .in = addr },
            .ipv6 => |addr| .{ .in6 = addr },
        };
    }
};

/// A Varlink address.
pub const Address = union(enum) {
    tcp: TcpAddress,
    /// A device node.
    device: []const u8,

    /// Format the address into its string form.
    pub fn format(
        self: Address,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        try out_stream.writeAll(@tagName(self));
        try out_stream.writeByte(':');
        switch (self) {
            .tcp => |addr| try addr.format(fmt, options, out_stream),
            .device => |dev| try out_stream.writeAll(dev),
        }
    }

    const ParseTcpError = error{
        MissingClosingBracket,
        MissingPort,
        InvalidPort,
        InvalidAddress,
    };

    fn parseTcp(address: []const u8) ParseTcpError!TcpAddress {
        if (address[0] == '[') {
            const ipv6_end = std.mem.indexOfScalar(u8, address, ']') orelse
                return error.MissingClosingBracket;
            if (ipv6_end >= address.len - 2 or address[ipv6_end + 1] != ':') {
                return error.MissingPort;
            }
            const port = std.fmt.parseInt(u16, address[ipv6_end + 2 ..], 10) catch
                return error.InvalidPort;
            const net_address = std.net.Address.parseIp6(
                address[1..ipv6_end],
                port,
            ) catch return error.InvalidAddress;
            return .{ .ipv6 = net_address.in6 };
        } else {
            const colon_position = std.mem.indexOfScalar(u8, address, ':') orelse
                return error.MissingPort;
            if (colon_position == address.len - 1) {
                return error.MissingPort;
            }
            const port = std.fmt.parseInt(u16, address[colon_position + 1 ..], 10) catch
                return error.InvalidPort;
            const net_address = std.net.Address.parseIp4(
                address[0..colon_position],
                port,
            ) catch return error.InvalidAddress;
            return .{ .ipv4 = net_address.in };
        }
    }

    test "parseTcp can handle IPv4" {
        {
            const address = "127.0.0.1:1234";
            const parsed = try parseTcp(address);
            const string_form = try std.fmt.allocPrint(
                std.testing.allocator,
                "{}",
                .{parsed},
            );
            defer std.testing.allocator.free(string_form);
            try std.testing.expectEqualStrings("127.0.0.1:1234", string_form);
        }
        {
            const address = "127.0.0.1";
            try std.testing.expectError(error.MissingPort, parseTcp(address));
        }
        {
            const address = "127.0.0.1:";
            try std.testing.expectError(error.MissingPort, parseTcp(address));
        }
        {
            const address = "127.0.0.1:-1";
            try std.testing.expectError(error.InvalidPort, parseTcp(address));
        }
        {
            const address = "609.609.609.609:0";
            try std.testing.expectError(error.InvalidAddress, parseTcp(address));
        }
    }

    test "parseTcp can handle IPv6" {
        {
            const address = "[::1]:1234";
            const parsed = try parseTcp(address);
            const string_form = try std.fmt.allocPrint(
                std.testing.allocator,
                "{}",
                .{parsed},
            );
            defer std.testing.allocator.free(string_form);
            try std.testing.expectEqualStrings("[::1]:1234", string_form);
        }
        {
            const address = "[::1]";
            try std.testing.expectError(error.MissingPort, parseTcp(address));
        }
        {
            const address = "[::1]:";
            try std.testing.expectError(error.MissingPort, parseTcp(address));
        }
        {
            const address = "[::1]:-1";
            try std.testing.expectError(error.InvalidPort, parseTcp(address));
        }
        {
            const address = "[:::1]:0";
            try std.testing.expectError(error.InvalidAddress, parseTcp(address));
        }
        {
            const address = "[::1";
            try std.testing.expectError(error.MissingClosingBracket, parseTcp(address));
        }
    }

    pub const ParseError = ParseTcpError || error{
        MissingAddress,
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
                return .{ .tcp = try parseTcp(effective_address[colon_position + 1 ..]) };
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
                "{}",
                .{parsed},
            );
            defer std.testing.allocator.free(string_form);
            try std.testing.expectEqualStrings("tcp:127.0.0.1:1234", string_form);
        }
        {
            const address = "device:/dev/null;options=123";
            const parsed = try parse(address);
            const string_form = try std.fmt.allocPrint(
                std.testing.allocator,
                "{}",
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
            const address = "udp:127.0.0.1:0";
            try std.testing.expectError(error.UnknownScheme, parse(address));
        }
    }
};
