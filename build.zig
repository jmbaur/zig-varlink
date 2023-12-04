// SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>
//
// SPDX-License-Identifier: Apache-2.0 OR MIT

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

    const router = b.createModule(.{
        .source_file = .{ .path = "router.zig" },
        .dependencies = &.{},
    });

    const orgVarlinkService = scanFile(
        b,
        scanner,
        "org.varlink.service.varlink",
        "orgVarlinkService.zig",
    );
    const handler = b.addModule("varlink-handler", .{
        .source_file = .{ .path = "handler.zig" },
        .dependencies = &[_]std.Build.ModuleDependency{
            .{
                .name = "orgVarlinkService",
                .module = orgVarlinkService,
            },
            .{
                .name = "router",
                .module = router,
            },
        },
    });

    const tokenizer_tests = b.addTest(.{
        .name = "tokenizer_tests",
        .root_source_file = .{ .path = "tokenizer.zig" },
        .target = target,
        .optimize = optimize,
    });
    const handler_tests = b.addTest(.{
        .name = "handler_tests",
        .root_source_file = .{ .path = "test/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    handler_tests.addModule("varlink-handler", handler);
    handler_tests.addModule(
        "zigVarlinkTest",
        scanFile(
            b,
            scanner,
            "test/org.zig-varlink.test.varlink",
            "zigVarlinkTest.zig",
        ),
    );

    const certification = b.addExecutable(.{
        .name = "zig-varlink-certification",
        .root_source_file = .{ .path = "test/certification.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    certification.addModule("varlink-handler", handler);
    certification.addModule(
        "orgVarlinkCertification",
        scanFile(
            b,
            scanner,
            "test/org.varlink.certification.varlink",
            "orgVarlinkCertification.zig",
        ),
    );
    b.installArtifact(certification);

    const test_step = b.step("test", "Run tests");
    const run_tokenizer_tests = b.addRunArtifact(tokenizer_tests);
    const run_handler_tests = b.addRunArtifact(handler_tests);
    test_step.dependOn(&run_tokenizer_tests.step);
    test_step.dependOn(&run_handler_tests.step);
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
