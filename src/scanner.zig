// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const Token = tokenizer.Token;

fn writeType(
    writer: *std.Io.Writer,
    tokens: []const Token,
) std.Io.Writer.Error![]const Token {
    var opened_dicts: usize = 0;
    const result = for (tokens, 0..) |token, i| {
        switch (token) {
            .maybe => try writer.writeByte('?'),
            .array => try writer.writeAll("[]const "),
            .dict => {
                opened_dicts += 1;
                try writer.writeAll("std.StringHashMapUnmanaged(");
            },
            .enum_begin => {
                break writeEnumBody(writer, tokens[i..]);
            },
            .struct_begin => {
                break writeStruct(writer, tokens[i..]);
            },
            .bool => {
                try writer.writeAll("bool");
                break tokens[i + 1 ..];
            },
            .int => {
                try writer.writeAll("i64");
                break tokens[i + 1 ..];
            },
            .float => {
                try writer.writeAll("f64");
                break tokens[i + 1 ..];
            },
            .string => {
                try writer.writeAll("[]const u8");
                break tokens[i + 1 ..];
            },
            .object => {
                try writer.writeAll("std.json.Value");
                break tokens[i + 1 ..];
            },
            .name => |name| {
                try writer.writeAll(name);
                break tokens[i + 1 ..];
            },
            else => unreachable,
        }
    } else unreachable;
    for (0..opened_dicts) |_| {
        try writer.writeByte(')');
    }
    return result;
}

fn writeEnumBody(
    writer: *std.Io.Writer,
    tokens: []const Token,
) std.Io.Writer.Error![]const Token {
    std.debug.assert(tokens[0] == .enum_begin);
    try writer.writeAll("enum {\n");
    var current_tokens = tokens[1..];
    while (current_tokens[0] != .enum_end) {
        const name = current_tokens[0].name;
        try writer.writeAll(name);
        try writer.writeAll(",\n");
        current_tokens = current_tokens[1..];
    }
    try writer.writeByte('}');
    return current_tokens[1..];
}

fn writeStructFields(
    writer: *std.Io.Writer,
    tokens: []const Token,
) std.Io.Writer.Error![]const Token {
    std.debug.assert(tokens[0] == .struct_begin);
    var current_tokens = tokens[1..];
    while (current_tokens[0] != .struct_end) {
        const name = current_tokens[0].name;
        try writer.writeAll("@\"");
        // Varlink names aren't allowed to contain quotes, so this should be
        // fine.
        try writer.writeAll(name);
        try writer.writeAll("\": ");
        current_tokens = try writeType(writer, current_tokens[1..]);
        try writer.writeAll(",\n");
    }
    return current_tokens;
}

fn writeStruct(
    writer: *std.Io.Writer,
    tokens: []const Token,
) std.Io.Writer.Error![]const Token {
    try writer.writeAll("struct {\n");
    const struct_end = try writeStructFields(writer, tokens);
    try writer.writeByte('}');
    return struct_end[1..];
}

fn writeMethod(
    writer: *std.Io.Writer,
    tokens: []const Token,
) std.Io.Writer.Error![]const Token {
    std.debug.assert(tokens[0] == .method);
    try writer.writeAll("pub const ");
    try writer.writeAll(tokens[1].name);
    try writer.writeAll(" = struct {\npub const Parameters = ");
    const after_params = try writeStruct(writer, tokens[2..]);
    try writer.writeAll(";\npub const ReturnType = ");
    const after_ret_type = try writeStruct(writer, after_params);
    try writer.writeAll(";\n};\n");
    return after_ret_type;
}

fn writeError(
    writer: *std.Io.Writer,
    tokens: []const Token,
) std.Io.Writer.Error![]const Token {
    std.debug.assert(tokens[0] == .@"error");
    try writer.writeAll("pub const ");
    try writer.writeAll(tokens[1].name);
    try writer.writeAll(" = struct {\npub const error_name = interface.name ++ ");
    try writer.writeAll("\".");
    try writer.writeAll(tokens[1].name);
    try writer.writeAll("\";\n");
    const struct_end = try writeStructFields(writer, tokens[2..]);
    try writer.writeAll("};\n");
    return struct_end[1..];
}

fn writeTypedef(
    writer: *std.Io.Writer,
    tokens: []const Token,
) std.Io.Writer.Error![]const Token {
    std.debug.assert(tokens[0] == .typedef);
    try writer.writeAll("pub const ");
    try writer.writeAll(tokens[1].name);
    try writer.writeAll(" = ");
    const after_type = if (tokens[2] == .struct_begin)
        try writeStruct(writer, tokens[2..])
    else
        try writeEnumBody(writer, tokens[2..]);
    try writer.writeAll(";\n");
    return after_type;
}

fn writeMember(
    writer: *std.Io.Writer,
    tokens: []const Token,
) std.Io.Writer.Error![]const Token {
    return switch (tokens[0]) {
        .method => writeMethod(writer, tokens),
        .@"error" => writeError(writer, tokens),
        .typedef => writeTypedef(writer, tokens),
        else => unreachable,
    };
}

fn writeInterface(
    writer: *std.Io.Writer,
    tokens: []const Token,
    description: []const u8,
) std.Io.Writer.Error!void {
    try writer.writeAll("const std = @import(\"std\");\n" ++
        "const interface = @This();\n" ++
        "pub const name = \"");
    try writer.writeAll(tokens[0].name);
    // TODO: Somehow use @embedFile instead?
    try writer.writeAll("\";\npub const description =");
    var line_iterator = std.mem.tokenizeScalar(u8, description, '\n');
    while (line_iterator.next()) |line| {
        try writer.writeAll("\n\\\\");
        try writer.writeAll(line);
    }
    try writer.writeAll("\n\\\\\n;\n");
    var current_tokens = tokens[1..];
    while (current_tokens.len > 0) {
        current_tokens = try writeMember(writer, current_tokens);
    }
}

fn expectArgumentMessage(writer: anytype, expected: u32, got: u32) !void {
    try writer.print("Expected {} arguments, got: {}\n", .{ expected, got });
}

const Arguments = struct {
    input_path: [:0]const u8,
    output_path: [:0]const u8,

    fn parse(writer: anytype, args: *std.process.Args.Iterator) !Arguments {
        if (!args.skip()) {
            try writer.writeAll("Missing program name as first argument!\n");
            return error.InvalidArguments;
        }
        const input_path = args.next() orelse {
            try expectArgumentMessage(writer, 2, 0);
            return error.InvalidArguments;
        };
        const output_path = args.next() orelse {
            try expectArgumentMessage(writer, 2, 1);
            return error.InvalidArguments;
        };
        if (args.skip()) {
            var arg_count: u32 = 3;
            while (args.skip()) {
                arg_count += 1;
            }
            try expectArgumentMessage(writer, 2, arg_count);
            return error.InvalidArguments;
        }
        return .{
            .input_path = input_path,
            .output_path = output_path,
        };
    }
};

pub fn main(init: std.process.Init) !void {
    var stderr_buffer: [256]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const allocator = init.arena.allocator();

    var args = init.minimal.args.iterate();
    defer args.deinit();
    const arguments = Arguments.parse(stderr, &args) catch {
        try stderr.flush();
        std.process.exit(1);
    };

    const input = getInput: {
        const input_file = std.Io.Dir.cwd().openFile(
            init.io,
            arguments.input_path,
            .{},
        ) catch |err| {
            try stderr.print("Failed to open the input file: {}\n", .{err});
            try stderr.flush();
            std.process.exit(1);
        };
        defer input_file.close(init.io);
        var input_reader = input_file.reader(init.io, &.{});
        break :getInput try input_reader.interface.allocRemaining(
            allocator,
            .unlimited,
        );
    };
    defer allocator.free(input);
    if (!std.unicode.utf8ValidateSlice(input)) {
        try stderr.writeAll("Input is not valid UTF-8!\n");
        try stderr.flush();
        std.process.exit(1);
    }
    // TODO: Error reporting using error_pos
    var error_pos: ?[*]const u8 = null;
    var tokens = try tokenizer.tokenize(input, &error_pos, allocator);
    defer tokens.deinit(allocator);

    const output_file = std.Io.Dir.cwd().createFile(
        init.io,
        arguments.output_path,
        .{},
    ) catch |err| {
        try stderr.print("Failed to create the output file: {}\n", .{err});
        try stderr.flush();
        std.process.exit(1);
    };
    defer output_file.close(init.io);
    var output_buffer: [4096]u8 = undefined;
    var output_writer = output_file.writer(init.io, &output_buffer);
    const output = &output_writer.interface;
    try writeInterface(output, tokens.items, input);
    try output.flush();
}
