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
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/scanner.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(scanner);

    const build_scanner = b.addExecutable(.{
        .name = "zig-varlink-scanner-for-build",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/scanner.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    const orgVarlinkService = scanFile(
        b,
        build_scanner,
        b.path("org.varlink.service.varlink"),
        "orgVarlinkService.zig",
    );
    const varlink = b.addModule("varlink", .{
        .root_source_file = b.path("src/varlink.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "orgVarlinkService",
                .module = orgVarlinkService,
            },
        },
    });

    const orgVarlinkCertification = scanFile(
        b,
        scanner,
        b.path("test/certification/org.varlink.certification.varlink"),
        "orgVarlinkCertification.zig",
    );

    const tokenizer_tests = b.addTest(.{
        .name = "tokenizer_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tokenizer.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const router_tests = b.addTest(.{
        .name = "router_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    router_tests.root_module.addImport("varlink", varlink);
    router_tests.root_module.addImport(
        "zigVarlinkTest",
        scanFile(
            b,
            scanner,
            b.path("test/org.zig-varlink.test.varlink"),
            "zigVarlinkTest.zig",
        ),
    );
    router_tests.root_module.addImport("orgVarlinkCertification", orgVarlinkCertification);
    const unit_tests = b.addTest(.{
        .name = "unit_tests",
        .root_module = varlink,
    });
    unit_tests.root_module.addImport("orgVarlinkService", orgVarlinkService);

    const certification = b.addExecutable(.{
        .name = "zig-varlink-certification",
        .root_module = b.createModule(
            .{
                .root_source_file = b.path("test/certification/certification.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            },
        ),
    });
    certification.root_module.addImport("varlink", varlink);
    certification.root_module.addImport("orgVarlinkCertification", orgVarlinkCertification);
    b.installArtifact(certification);

    const test_step = b.step("test", "Run tests");
    const run_tokenizer_tests = b.addRunArtifact(tokenizer_tests);
    const run_router_tests = b.addRunArtifact(router_tests);
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_tokenizer_tests.step);
    test_step.dependOn(&run_router_tests.step);
    test_step.dependOn(&run_unit_tests.step);
}

pub fn scanFile(
    b: *Build,
    scanner: *Build.Step.Compile,
    input_path: Build.LazyPath,
    output_path: []const u8,
) *Build.Module {
    const run = b.addRunArtifact(scanner);
    run.addFileArg(input_path);
    const module_source = run.addOutputFileArg(output_path);
    return b.createModule(.{ .root_source_file = module_source });
}
