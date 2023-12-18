// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const Token = tokenizer.Token;

fn writeType(
    stream: anytype,
    tokens: []const Token,
) @TypeOf(stream).Error![]const Token {
    var opened_dicts: usize = 0;
    const result = for (tokens, 0..) |token, i| {
        switch (token) {
            .maybe => try stream.writeByte('?'),
            .array => try stream.writeAll("[]const "),
            .dict => {
                opened_dicts += 1;
                try stream.writeAll("std.StringHashMapUnmanaged(");
            },
            .enum_begin => {
                break writeEnumBody(stream, tokens[i..]);
            },
            .struct_begin => {
                break writeStruct(stream, tokens[i..]);
            },
            .bool => {
                try stream.writeAll("bool");
                break tokens[i + 1 ..];
            },
            .int => {
                try stream.writeAll("i64");
                break tokens[i + 1 ..];
            },
            .float => {
                try stream.writeAll("f64");
                break tokens[i + 1 ..];
            },
            .string => {
                try stream.writeAll("[]const u8");
                break tokens[i + 1 ..];
            },
            .object => {
                try stream.writeAll("std.json.Value");
                break tokens[i + 1 ..];
            },
            .name => |name| {
                try stream.writeAll(name);
                break tokens[i + 1 ..];
            },
            else => unreachable,
        }
    } else unreachable;
    for (0..opened_dicts) |_| {
        try stream.writeByte(')');
    }
    return result;
}

fn writeEnumBody(
    stream: anytype,
    tokens: []const Token,
) @TypeOf(stream).Error![]const Token {
    std.debug.assert(tokens[0] == .enum_begin);
    try stream.writeAll("enum {\n");
    var current_tokens = tokens[1..];
    while (current_tokens[0] != .enum_end) {
        const name = current_tokens[0].name;
        try stream.writeAll(name);
        try stream.writeAll(",\n");
        current_tokens = current_tokens[1..];
    }
    try stream.writeByte('}');
    return current_tokens[1..];
}

fn writeStructFields(
    stream: anytype,
    tokens: []const Token,
) @TypeOf(stream).Error![]const Token {
    std.debug.assert(tokens[0] == .struct_begin);
    var current_tokens = tokens[1..];
    while (current_tokens[0] != .struct_end) {
        const name = current_tokens[0].name;
        try stream.writeAll("@\"");
        // Varlink names aren't allowed to contain quotes, so this should be
        // fine.
        try stream.writeAll(name);
        try stream.writeAll("\": ");
        current_tokens = try writeType(stream, current_tokens[1..]);
        try stream.writeAll(",\n");
    }
    return current_tokens;
}

fn writeStruct(
    stream: anytype,
    tokens: []const Token,
) @TypeOf(stream).Error![]const Token {
    try stream.writeAll("struct {\n");
    const struct_end = try writeStructFields(stream, tokens);
    try stream.writeByte('}');
    return struct_end[1..];
}

fn writeMethod(
    stream: anytype,
    tokens: []const Token,
) @TypeOf(stream).Error![]const Token {
    std.debug.assert(tokens[0] == .method);
    try stream.writeAll("pub const ");
    try stream.writeAll(tokens[1].name);
    try stream.writeAll(" = struct {\npub const Parameters = ");
    const after_params = try writeStruct(stream, tokens[2..]);
    try stream.writeAll(";\npub const ReturnType = ");
    const after_ret_type = try writeStruct(stream, after_params);
    try stream.writeAll(";\n};\n");
    return after_ret_type;
}

fn writeError(
    stream: anytype,
    tokens: []const Token,
) @TypeOf(stream).Error![]const Token {
    std.debug.assert(tokens[0] == .@"error");
    try stream.writeAll("pub const ");
    try stream.writeAll(tokens[1].name);
    try stream.writeAll(" = struct {\npub const error_name = interface.name ++ ");
    try stream.writeAll("\".");
    try stream.writeAll(tokens[1].name);
    try stream.writeAll("\";\n");
    const struct_end = try writeStructFields(stream, tokens[2..]);
    try stream.writeAll("};\n");
    return struct_end[1..];
}

fn writeTypedef(
    stream: anytype,
    tokens: []const Token,
) @TypeOf(stream).Error![]const Token {
    std.debug.assert(tokens[0] == .typedef);
    try stream.writeAll("pub const ");
    try stream.writeAll(tokens[1].name);
    try stream.writeAll(" = ");
    const after_type = if (tokens[2] == .struct_begin)
        try writeStruct(stream, tokens[2..])
    else
        try writeEnumBody(stream, tokens[2..]);
    try stream.writeAll(";\n");
    return after_type;
}

fn writeMember(
    stream: anytype,
    tokens: []const Token,
) @TypeOf(stream).Error![]const Token {
    return switch (tokens[0]) {
        .method => writeMethod(stream, tokens),
        .@"error" => writeError(stream, tokens),
        .typedef => writeTypedef(stream, tokens),
        else => unreachable,
    };
}

fn writeInterface(
    stream: anytype,
    tokens: []const Token,
    description: []const u8,
) @TypeOf(stream).Error!void {
    try stream.writeAll("const std = @import(\"std\");\n" ++
        "const interface = @This();\n" ++
        "pub const name = \"");
    try stream.writeAll(tokens[0].name);
    // TODO: Somehow use @embedFile instead?
    try stream.writeAll("\";\npub const description =");
    var line_iterator = std.mem.tokenizeScalar(u8, description, '\n');
    while (line_iterator.next()) |line| {
        try stream.writeAll("\n\\\\");
        try stream.writeAll(line);
    }
    try stream.writeAll("\n\\\\\n;\n");
    var current_tokens = tokens[1..];
    while (current_tokens.len > 0) {
        current_tokens = try writeMember(stream, current_tokens);
    }
}

fn expectArgumentMessage(writer: anytype, expected: u32, got: u32) !void {
    try writer.print("Expected {} arguments, got: {}\n", .{ expected, got });
}

const Arguments = struct {
    input_path: [:0]const u8,
    output_path: [:0]const u8,

    fn parse(writer: anytype, args: *std.process.ArgIterator) !Arguments {
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

pub fn main() !void {
    const stderr = std.io.getStdErr();
    var stderr_buf = std.io.bufferedWriter(stderr.writer());
    const stderr_writer = stderr_buf.writer();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    const arguments = Arguments.parse(stderr_writer, &args) catch {
        try stderr_buf.flush();
        std.os.exit(1);
    };

    const input = getInput: {
        const input_file = std.fs.cwd().openFileZ(
            arguments.input_path,
            .{},
        ) catch |err| {
            try stderr_writer.print("Failed to open the input file: {}\n", .{err});
            try stderr_buf.flush();
            std.os.exit(1);
        };
        defer input_file.close();
        break :getInput try input_file.readToEndAllocOptions(
            allocator,
            std.math.maxInt(usize),
            // Give a nice default size to reduce allocations
            4096,
            @alignOf(u8),
            null,
        );
    };
    defer allocator.free(input);
    if (!std.unicode.utf8ValidateSlice(input)) {
        try stderr.writer().writeAll("Input is not valid UTF-8!\n");
        std.os.exit(1);
    }
    // TODO: Error reporting using error_pos
    var error_pos: ?[*]const u8 = null;
    const tokens = try tokenizer.tokenize(input, &error_pos, allocator);
    defer tokens.deinit();

    const output_file = std.fs.cwd().createFileZ(
        arguments.output_path,
        .{},
    ) catch |err| {
        try stderr_writer.print("Failed to create the output file: {}\n", .{err});
        try stderr_buf.flush();
        std.os.exit(1);
    };
    defer output_file.close();
    var output_buf = std.io.bufferedWriter(output_file.writer());
    const output_writer = output_buf.writer();
    try writeInterface(output_writer, tokens.items, input);
    try output_buf.flush();
}
