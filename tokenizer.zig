// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

//! A tokenizer for Varlink interface files.

const std = @import("std");
const testing = std.testing;

pub const Token = union(enum) {
    name: []const u8,
    typedef,
    @"error",
    method,
    enum_begin,
    enum_end,
    struct_begin,
    struct_end,
    maybe,
    array,
    dict,
    bool,
    int,
    float,
    string,
    object,
};

pub const Tokens = std.ArrayList(Token);

/// Skip all whitespace until the end of the line. Returns a boolean containing
/// true if the EOL was reached and the rest of the string. Expects valid UTF-8
/// input.
fn skipLineWhitespace(input: []const u8) struct { bool, []const u8 } {
    var utf8 = std.unicode.Utf8View.initUnchecked(input).iterator();
    var in_comment = false;
    var start: usize = 0;
    while (utf8.nextCodepoint()) |codepoint| : ({
        start += std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
    }) {
        switch (codepoint) {
            '\n', '\r', '\u{2028}', '\u{2029}' => {
                return .{ true, input[start + 1 ..] };
            },
            ' ',
            '\t',
            '\u{00A0}',
            '\u{FEFF}',
            '\u{1680}',
            '\u{180E}',
            '\u{2000}'...'\u{200A}',
            '\u{202F}',
            '\u{205F}',
            '\u{3000}',
            => {},
            '#' => in_comment = true,
            else => if (!in_comment) break,
        }
    }
    return .{ false, input[start..] };
}

/// Skip all whitespace and comments at the start of the input and return the
/// rest of the string.
fn skipAllWhitespace(input: []const u8) []const u8 {
    var current_input = input;
    while (true) {
        const result = skipLineWhitespace(current_input);
        if (!result[0]) {
            return result[1];
        }
        current_input = result[1];
    }
}

test skipAllWhitespace {
    try testing.expectEqualStrings("a", skipAllWhitespace("a"));
    try testing.expectEqualStrings("a", skipAllWhitespace(" \u{00A0}\t\na"));
    try testing.expectEqualStrings("test ", skipAllWhitespace("\n # comment\ntest "));
    try testing.expectEqualStrings("test ", skipAllWhitespace("# ¯\\_(ツ)_/¯ \ntest "));
}

/// Skip all whitespace and comments until EOL. Returns error.ExpectedEol if an
/// EOL was not found and sets error_pos.
fn skipEol(input: []const u8, error_pos: *?[*]const u8) error{ExpectedEol}![]const u8 {
    const result = skipLineWhitespace(input);
    if (result[0]) {
        return result[1];
    } else {
        if (result[1].len > 0) {
            error_pos.* = result[1].ptr;
        }
        return error.ExpectedEol;
    }
}

test skipEol {
    var error_pos: ?[*]const u8 = null;
    try testing.expectEqualStrings("a", try skipEol("\na", &error_pos));
    try testing.expectEqualStrings(
        " \na",
        try skipEol(" \t # test\n \na", &error_pos),
    );
    const testString = "a\n";
    try testing.expectError(error.ExpectedEol, skipEol(testString, &error_pos));
    try testing.expectEqual(testString.ptr, error_pos.?);
}

/// Skip the given word from the start of input and return the rest of the
/// input. Returns error.ExpectedWord if the input doesn't start with the word
/// and sets error_pos.
fn skipWord(
    input: []const u8,
    word: []const u8,
    error_pos: *?[*]const u8,
) error{ExpectedWord}![]const u8 {
    if (!std.mem.startsWith(u8, input, word)) {
        if (input.len > 0) {
            error_pos.* = input.ptr;
        }
        return error.ExpectedWord;
    }
    return input[word.len..];
}

test skipWord {
    var error_pos: ?[*]const u8 = null;
    try testing.expectEqualStrings(
        "a",
        try skipWord(
            "testa",
            "test",
            &error_pos,
        ),
    );
    const testString = "test";
    try testing.expectError(
        error.ExpectedWord,
        skipWord(
            testString,
            "a",
            &error_pos,
        ),
    );
    try testing.expectEqual(testString.ptr, error_pos.?);
}

/// Tokenize a Varlink name into a .name token and return the rest of the input.
/// This allows a much more liberal use of characters than the spec. Returns
/// error.InvalidName and sets error_pos.* if the input doesn't start
/// with a valid name.
fn tokenizeName(
    input: []const u8,
    tokens: *Tokens,
    error_pos: *?[*]const u8,
) ![]const u8 {
    for (input, 0..) |c, i| {
        switch (c) {
            '0'...'9', 'A'...'Z', 'a'...'z', '_', '-', '.' => {},
            else => {
                if (i == 0) {
                    error_pos.* = input.ptr;
                    return error.InvalidName;
                }
                try tokens.append(.{ .name = input[0..i] });
                return input[i..];
            },
        }
    }
    if (input.len == 0) {
        return error.InvalidName;
    }
    try tokens.append(.{ .name = input });
    return &.{};
}

test tokenizeName {
    const gpa = std.testing.allocator;
    var tokens = Tokens.init(gpa);
    defer tokens.deinit();
    var error_pos: ?[*]const u8 = null;
    try testing.expectEqualStrings(
        "",
        try tokenizeName(
            "test",
            &tokens,
            &error_pos,
        ),
    );
    try testing.expectEqual(@as(usize, 1), tokens.items.len);
    try testing.expectEqualDeep(Token{ .name = "test" }, tokens.items[0]);
    try testing.expectEqualStrings(
        " ",
        try tokenizeName(
            "test ",
            &tokens,
            &error_pos,
        ),
    );
    try testing.expectEqual(@as(usize, 2), tokens.items.len);
    try testing.expectEqualDeep(Token{ .name = "test" }, tokens.items[1]);
    const testString = ": bool";
    try testing.expectError(
        error.InvalidName,
        tokenizeName(
            testString,
            &tokens,
            &error_pos,
        ),
    );
    try testing.expectEqual(testString.ptr, error_pos.?);
    error_pos = null;
    try testing.expectEqual(@as(usize, 2), tokens.items.len);
}

/// Tokenize a Varlink interface into a .name token and return the rest of the
/// input.
fn tokenizeInterface(
    input: []const u8,
    tokens: *Tokens,
    error_pos: *?[*]const u8,
) ![]const u8 {
    const after_interface = skipWord(input, "interface", &error_pos.*) catch
        return error.ExpectedInterfaceKeyword;
    const name_start = skipAllWhitespace(after_interface);
    const eol_start = try tokenizeName(name_start, tokens, error_pos);
    return skipEol(eol_start, error_pos);
}

test tokenizeInterface {
    const gpa = std.testing.allocator;
    var tokens = Tokens.init(gpa);
    defer tokens.deinit();
    var error_pos: ?[*]const u8 = null;
    const test_string = "interface\n org.varlink.service \n test";
    const expected_token: Token = .{ .name = "org.varlink.service" };
    try testing.expectEqualStrings(
        " test",
        try tokenizeInterface(
            test_string,
            &tokens,
            &error_pos,
        ),
    );
    try testing.expectEqual(@as(usize, 1), tokens.items.len);
    try testing.expectEqualDeep(expected_token, tokens.items[0]);
}

const TokenizeTypeError = error{ExpectedType} || std.mem.Allocator.Error || TokenizeStructlikeError;

fn tokenizeType(
    input: []const u8,
    tokens: *Tokens,
    error_pos: *?[*]const u8,
) TokenizeTypeError![]const u8 {
    var dummy_error_pos: ?[*]const u8 = null;
    if (skipWord(input, "bool", &dummy_error_pos)) |rest| {
        try tokens.append(.bool);
        return rest;
    } else |_| if (skipWord(input, "int", &dummy_error_pos)) |rest| {
        try tokens.append(.int);
        return rest;
    } else |_| if (skipWord(input, "float", &dummy_error_pos)) |rest| {
        try tokens.append(.int);
        return rest;
    } else |_| if (skipWord(input, "string", &dummy_error_pos)) |rest| {
        try tokens.append(.string);
        return rest;
    } else |_| if (skipWord(input, "[string]", &dummy_error_pos)) |rest| {
        try tokens.append(.dict);
        return tokenizeType(rest, tokens, error_pos);
    } else |_| if (skipWord(input, "[]", &dummy_error_pos)) |rest| {
        try tokens.append(.array);
        return tokenizeType(rest, tokens, &dummy_error_pos);
    } else |_| if (skipWord(input, "?", &dummy_error_pos)) |rest| {
        try tokens.append(.maybe);
        // TODO: Ban multiple question marks in a row?
        return tokenizeType(rest, tokens, error_pos);
    } else |_| if (skipWord(input, "object", &dummy_error_pos)) |rest| {
        try tokens.append(.object);
        return rest;
    } else |_| {
        if (input.len == 0 or input[0] != '(') {
            return tokenizeName(input, tokens, error_pos);
        }
        return tokenizeStructlike(input, tokens, error_pos);
    }
}

test tokenizeType {
    const gpa = std.testing.allocator;
    var tokens = Tokens.init(gpa);
    defer tokens.deinit();
    var error_pos: ?[*]const u8 = null;
    const rest = try tokenizeType("?[](first: int, second: string) ", &tokens, &error_pos);
    try testing.expectEqualStrings(" ", rest);
    try testing.expectEqual(@as(usize, 8), tokens.items.len);
    try testing.expectEqual(Token.maybe, tokens.items[0]);
    try testing.expectEqual(Token.array, tokens.items[1]);
    try testing.expectEqual(Token.struct_begin, tokens.items[2]);
    try testing.expectEqualDeep(Token{ .name = "first" }, tokens.items[3]);
    try testing.expectEqual(Token.int, tokens.items[4]);
    try testing.expectEqualDeep(Token{ .name = "second" }, tokens.items[5]);
    try testing.expectEqual(Token.string, tokens.items[6]);
    try testing.expectEqual(Token.struct_end, tokens.items[7]);
    try testing.expect(error_pos == null);
}

const TokenizeEnumFieldsError = error{
    InvalidName,
    UnclosedEnum,
    ExpectedComma,
} || std.mem.Allocator.Error;

fn tokenizeEnumFields(
    input: []const u8,
    tokens: *Tokens,
    error_pos: *?[*]const u8,
) TokenizeEnumFieldsError![]const u8 {
    var current_input = input;
    while (true) {
        const rest = try tokenizeName(current_input, tokens, error_pos);
        current_input = skipAllWhitespace(rest);
        if (current_input.len == 0) {
            if (rest.len > 0) {
                error_pos.* = rest.ptr;
            }
            return error.UnclosedEnum;
        }
        switch (current_input[0]) {
            ',' => current_input = skipAllWhitespace(current_input[1..]),
            ')' => {
                try tokens.append(.enum_end);
                return current_input[1..];
            },
            else => {
                error_pos.* = current_input.ptr;
                return error.ExpectedComma;
            },
        }
    }
}

// Because tokenizeType and tokenizeStructLike indirectly call each other with
// try, their error types are dependent on each other. Thus, TokenizeTypeError
// is not included in this error set and is only marked to the dependent
// function declarations instead.
const TokenizeStructFieldsError = error{
    InvalidName,
    ExpectedColon,
    UnclosedStruct,
    ExpectedComma,
} || std.mem.Allocator.Error;

fn tokenizeStructFields(
    input: []const u8,
    tokens: *Tokens,
    error_pos: *?[*]const u8,
) (TokenizeTypeError || TokenizeStructlikeError)![]const u8 {
    var current_input = input;
    while (true) {
        if (current_input.len == 0) {
            error_pos.* = input.ptr;
            return error.UnclosedStruct;
        }
        if (current_input[0] == ')') {
            try tokens.append(.struct_end);
            return current_input[1..];
        }

        const after_name = skipAllWhitespace(
            try tokenizeName(
                current_input,
                tokens,
                error_pos,
            ),
        );
        const before_type = skipAllWhitespace(
            skipWord(
                after_name,
                ":",
                error_pos,
            ) catch return error.ExpectedColon,
        );
        current_input = skipAllWhitespace(try tokenizeType(before_type, tokens, error_pos));
        if (current_input.len == 0) {
            error_pos.* = input.ptr;
            return error.UnclosedStruct;
        }
        switch (current_input[0]) {
            ',' => current_input = skipAllWhitespace(current_input[1..]),
            ')' => {},
            else => {
                error_pos.* = current_input.ptr;
                return error.ExpectedComma;
            },
        }
    }
}

const TokenizeStructlikeError = error{
    ExpectedOpeningParenthesis,
    UnclosedStructlike,
    ExpectedCommaOrColon,
} || TokenizeEnumFieldsError || TokenizeStructFieldsError;

fn tokenizeStructlike(
    input: []const u8,
    tokens: *Tokens,
    error_pos: *?[*]const u8,
) (TokenizeTypeError || TokenizeStructlikeError)![]const u8 {
    const after_opening = skipWord(input, "(", error_pos) catch
        return error.ExpectedOpeningParenthesis;
    const first_member = skipAllWhitespace(after_opening);
    const start_marker = try tokens.addOne();
    const after_name = skipAllWhitespace(
        try tokenizeName(
            first_member,
            tokens,
            error_pos,
        ),
    );
    if (after_name.len == 0) {
        error_pos.* = input.ptr;
        return error.UnclosedStructlike;
    }
    switch (after_name[0]) {
        ')' => {
            start_marker.* = .enum_begin;
            return after_name[1..];
        },
        ',' => {
            start_marker.* = .enum_begin;
            return tokenizeEnumFields(
                skipAllWhitespace(after_name[1..]),
                tokens,
                error_pos,
            );
        },
        ':' => {
            start_marker.* = .struct_begin;
            // It's easier to make tokenizeStructFields start from the first
            // member name instead of the first type. Therefore, drop the name
            // and let tokenizeStructFields add it back.
            _ = tokens.pop();
            return tokenizeStructFields(first_member, tokens, error_pos);
        },
        else => {
            error_pos.* = after_name.ptr;
            return error.ExpectedCommaOrColon;
        },
    }
}

fn tokenizeStruct(input: []const u8, tokens: *Tokens, error_pos: *?[*]const u8) ![]const u8 {
    if (input.len == 0) {
        return error.ExpectedStruct;
    }
    if (input[0] != '(') {
        error_pos.* = input.ptr;
        return error.ExpectedStruct;
    }
    try tokens.append(.struct_begin);
    return tokenizeStructFields(skipAllWhitespace(input[1..]), tokens, error_pos);
}

fn tokenizeTypedef(
    input: []const u8,
    tokens: *Tokens,
    error_pos: *?[*]const u8,
) ![]const u8 {
    const after_type = try skipWord(input, "type", error_pos);
    const after_space = skipAllWhitespace(after_type);
    if (after_space.len == 0) {
        error_pos.* = input.ptr;
        return error.ExpectedType;
    }
    if (after_space.ptr == after_type.ptr) {
        error_pos.* = after_space.ptr;
        return error.ExpectedSpace;
    }
    try tokens.append(.typedef);
    const after_name = try tokenizeName(after_space, tokens, error_pos);
    return skipEol(
        try tokenizeStructlike(
            skipAllWhitespace(after_name),
            tokens,
            error_pos,
        ),
        error_pos,
    );
}

test "tokenizeTypedef can handle enums" {
    const gpa = std.testing.allocator;
    var tokens = Tokens.init(gpa);
    defer tokens.deinit();
    var error_pos: ?[*]const u8 = null;

    const test_string = "type Test ( a , b ) \n ";
    try testing.expectEqualStrings(
        " ",
        try tokenizeTypedef(
            test_string,
            &tokens,
            &error_pos,
        ),
    );
    try testing.expectEqual(@as(usize, 6), tokens.items.len);
    try testing.expectEqual(Token.typedef, tokens.items[0]);
    try testing.expectEqualDeep(Token{ .name = "Test" }, tokens.items[1]);
    try testing.expectEqual(Token.enum_begin, tokens.items[2]);
    try testing.expectEqualDeep(Token{ .name = "a" }, tokens.items[3]);
    try testing.expectEqualDeep(Token{ .name = "b" }, tokens.items[4]);
    try testing.expectEqual(Token.enum_end, tokens.items[5]);
}

test "tokenizeTypedef can handle structs" {
    const gpa = std.testing.allocator;
    var tokens = Tokens.init(gpa);
    defer tokens.deinit();
    var error_pos: ?[*]const u8 = null;

    const test_string = "type Test ( a: int , b: ?int )\n";
    try testing.expectEqualStrings(
        "",
        try tokenizeTypedef(
            test_string,
            &tokens,
            &error_pos,
        ),
    );
    try testing.expectEqual(@as(usize, 9), tokens.items.len);
    try testing.expectEqual(Token.typedef, tokens.items[0]);
    try testing.expectEqualDeep(Token{ .name = "Test" }, tokens.items[1]);
    try testing.expectEqual(Token.struct_begin, tokens.items[2]);
    try testing.expectEqualDeep(Token{ .name = "a" }, tokens.items[3]);
    try testing.expectEqual(Token.int, tokens.items[4]);
    try testing.expectEqualDeep(Token{ .name = "b" }, tokens.items[5]);
    try testing.expectEqual(Token.maybe, tokens.items[6]);
    try testing.expectEqual(Token.int, tokens.items[7]);
    try testing.expectEqual(Token.struct_end, tokens.items[8]);
}

fn tokenizeError(input: []const u8, tokens: *Tokens, error_pos: *?[*]const u8) ![]const u8 {
    const after_error = skipWord(input, "error", error_pos) catch
        return error.ExpectedError;
    const after_space = skipAllWhitespace(after_error);
    if (after_space.len == 0) {
        error_pos.* = input.ptr;
        return error.ExpectedError;
    }
    if (after_space.ptr == after_error.ptr) {
        error_pos.* = after_space.ptr;
        return error.ExpectedSpace;
    }
    try tokens.append(.@"error");
    const after_name = try tokenizeName(after_space, tokens, error_pos);
    return skipEol(
        try tokenizeStruct(
            skipAllWhitespace(after_name),
            tokens,
            error_pos,
        ),
        error_pos,
    );
}

test tokenizeError {
    const gpa = testing.allocator;
    var tokens = Tokens.init(gpa);
    defer tokens.deinit();
    var error_pos: ?[*]const u8 = null;
    try testing.expectEqualStrings(
        " ",
        try tokenizeError(
            "error test ( ) \n ",
            &tokens,
            &error_pos,
        ),
    );
    try testing.expectEqual(@as(usize, 4), tokens.items.len);
    try testing.expectEqual(Token.@"error", tokens.items[0]);
    try testing.expectEqualDeep(Token{ .name = "test" }, tokens.items[1]);
    try testing.expectEqual(Token.struct_begin, tokens.items[2]);
    try testing.expectEqual(Token.struct_end, tokens.items[3]);
}

fn tokenizeMethod(input: []const u8, tokens: *Tokens, error_pos: *?[*]const u8) ![]const u8 {
    const after_method = skipWord(input, "method", error_pos) catch
        return error.ExpectedError;
    const after_space = skipAllWhitespace(after_method);
    if (after_space.len == 0) {
        error_pos.* = input.ptr;
        return error.ExpectedError;
    }
    if (after_space.ptr == after_method.ptr) {
        error_pos.* = after_space.ptr;
        return error.ExpectedSpace;
    }
    try tokens.append(.method);
    const after_name = try tokenizeName(after_space, tokens, error_pos);
    const after_first = skipAllWhitespace(try tokenizeStruct(
        skipAllWhitespace(after_name),
        tokens,
        error_pos,
    ));
    const after_arrow = skipAllWhitespace(
        skipWord(
            after_first,
            "->",
            error_pos,
        ) catch return error.ExpectedArrow,
    );
    return skipEol(
        try tokenizeStruct(after_arrow, tokens, error_pos),
        error_pos,
    );
}

test tokenizeMethod {
    const gpa = testing.allocator;
    var tokens = Tokens.init(gpa);
    defer tokens.deinit();
    var error_pos: ?[*]const u8 = null;
    try testing.expectEqualStrings(
        " ",
        try tokenizeMethod("method test () -> () \n ", &tokens, &error_pos),
    );
    try testing.expectEqual(@as(usize, 6), tokens.items.len);
    try testing.expectEqual(Token.method, tokens.items[0]);
    try testing.expectEqualDeep(Token{ .name = "test" }, tokens.items[1]);
    try testing.expectEqual(Token.struct_begin, tokens.items[2]);
    try testing.expectEqual(Token.struct_end, tokens.items[3]);
    try testing.expectEqual(Token.struct_begin, tokens.items[4]);
    try testing.expectEqual(Token.struct_end, tokens.items[5]);
}

pub fn tokenize(input: []const u8, error_pos: *?[*]const u8, allocator: std.mem.Allocator) !Tokens {
    var tokens = Tokens.init(allocator);
    errdefer tokens.deinit();
    const before_interface = skipAllWhitespace(input);
    const after_interface = try tokenizeInterface(before_interface, &tokens, error_pos);
    var current_input = after_interface;
    while (true) {
        current_input = skipAllWhitespace(current_input);
        if (current_input.len == 0) {
            break;
        }
        switch (current_input[0]) {
            'm' => current_input = try tokenizeMethod(current_input, &tokens, error_pos),
            't' => current_input = try tokenizeTypedef(current_input, &tokens, error_pos),
            'e' => current_input = try tokenizeError(current_input, &tokens, error_pos),
            else => {},
        }
    }
    return tokens;
}
