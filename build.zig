const std = @import("std");
const soundio = @import("third_party/zig-soundio/build.zig");
const tinyosc = @import("third_party/zig-tinyosc/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cli_module = b.addModule("cli", .{
        .source_file = .{ .path = "third_party/zig-cli/src/main.zig" },
    });
    const network_module = b.addModule("network", .{
        .source_file = .{ .path = "third_party/zig-network/network.zig" },
    });
    const soundio_module = soundio.module(b);
    const tinyosc_module = tinyosc.module(b);

    const dawn_module = b.addModule("dawn", .{
        .source_file = .{ .path = "src/main.zig" },
        .dependencies = &.{
            .{ .name = "cli", .module = cli_module },
            .{ .name = "network", .module = network_module },
            .{ .name = "soundio", .module = soundio_module },
            .{ .name = "tinyosc", .module = tinyosc_module },
        },
    });

    const server_exe = b.addExecutable(.{
        .name = "dawn",
        .root_source_file = .{ .path = "dawn.zig" },
        .target = target,
        .optimize = optimize,
    });
    server_exe.addModule("cli", cli_module);
    server_exe.addModule("dawn", dawn_module);
    soundio.link(b, server_exe);
    tinyosc.link(b, server_exe);
    b.installArtifact(server_exe);

    const server_cmd = b.addRunArtifact(server_exe);
    server_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        server_cmd.addArgs(args);
    }
    const server_step = b.step("dawn", "Run dawn");
    server_step.dependOn(&server_cmd.step);


    const client_exe = b.addExecutable(.{
        .name = "dusk",
        .root_source_file = .{ .path = "dusk.zig" },
        .target = target,
        .optimize = optimize,
    });
    client_exe.addModule("cli", cli_module);
    client_exe.addModule("dawn", dawn_module);
    client_exe.addModule("network", network_module);
    tinyosc.link(b, client_exe);
    b.installArtifact(client_exe);

    const client_cmd = b.addRunArtifact(client_exe);
    client_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        client_cmd.addArgs(args);
    }
    const client_step = b.step("dusk", "Run dusk");
    client_step.dependOn(&client_cmd.step);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_artifact = b.addRunArtifact(main_tests);
    main_tests.addModule("dawn", dawn_module);
    main_tests.addModule("network", network_module);
    main_tests.addModule("soundio", soundio_module);
    main_tests.addModule("tinyosc", tinyosc_module);
    soundio.link(b, main_tests);
    tinyosc.link(b, main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&test_artifact.step);
}
