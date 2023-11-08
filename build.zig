// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = b.addExecutable(.{
        .name = "zig-varlink-scanner",
        .root_source_file = .{ .path = "scanner.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(scanner);

    const tokenizer_tests = b.addTest(.{
        .name = "tokenizer_tests",
        .root_source_file = .{ .path = "tokenizer.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run tests");
    const run_tokenizer_tests = b.addRunArtifact(tokenizer_tests);
    test_step.dependOn(&run_tokenizer_tests.step);
}

pub fn scanFile(
    b: *Build,
    scanner: *Build.Step.Compile,
    input_path: []const u8,
    output_path: []const u8,
) *Build.Module {
    const run = b.addRunArtifact(scanner);
    run.addFileArg(.{ .path = input_path });
    const module_source = run.addOutputFileArg(output_path);
    return b.createModule(.{ .source_file = module_source });
}
