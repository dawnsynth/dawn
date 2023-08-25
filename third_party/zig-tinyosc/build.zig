const std = @import("std");

const src_path = root() ++ "/tinyosc.zig";

inline fn root() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

pub fn module(b: *std.Build) *std.build.Module {
    return b.createModule(.{ .source_file = .{ .path = src_path } });
}

pub fn link(b: *std.Build, exe: *std.build.LibExeObjStep) void {
    const target = exe.target;
    const optimize = exe.optimize;

    const lib = buildC(b, target, optimize);
    exe.linkLibrary(lib);

    exe.linkLibC();
    exe.addIncludePath(.{ .path = root() ++ "/tinyosc"});

    exe.step.dependOn(&lib.step);
}

fn buildC(b: *std.Build, target: std.zig.CrossTarget, optimize: std.builtin.Mode) *std.build.LibExeObjStep {
    const cflags = [_][]const u8{
        "-Wall",
        "-std=c99",
        "-pedantic",
        "-fsanitize=undefined",
    };
    const csources = [_][]const u8{
        root() ++ "/tinyosc/tinyosc.c",
    };

    const lib = b.addStaticLibrary(.{
        .name = "tinyosc",
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC();
    lib.addIncludePath(.{ .path = root() ++ "/tinyosc"});
    lib.addCSourceFiles(&csources, &cflags);

    b.installArtifact(lib);
    return lib;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tinyosc_mod = module(b);

    const demo = b.addExecutable(.{
        .name = "demo'",
        .root_source_file = .{ .path = "demo.zig" },
        .target = target,
        .optimize = optimize,
    });
    demo.addModule("tinyosc", tinyosc_mod);
    link(b, demo);
    b.installArtifact(demo);

    const run_cmd = b.addRunArtifact(demo);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
