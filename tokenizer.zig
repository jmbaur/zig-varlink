// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0

//! A tokenizer for Varlink interface files.

const std = @import("std");
const testing = std.testing;

const Token = union(enum) {
    name: []const u8,
};

const Tokens = std.ArrayList(Token);

/// Skip all whitespace until the end of the line. Returns a boolean containing
/// true if the EOL was reached and the rest of the string. Expects valid UTF-8
/// input.
fn skipLineWhitespace(input: []const u8) struct { bool, []const u8 } {
    var utf8 = std.unicode.Utf8View.initUnchecked(input).iterator();
    var in_comment = false;
    var start: usize = 0;
    while (utf8.nextCodepoint()) |codepoint| : (start += 1) {
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
    return skipEol(eol_start, &error_pos.*);
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
