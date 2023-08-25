const std = @import("std");

const src_path = root() ++ "/src/soundio.zig";

inline fn root() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

pub fn module(b: *std.Build) *std.build.Module {
    return b.createModule(.{ .source_file = .{ .path = src_path } });
}

/// Build and link libsoundio C library to given exe.
pub fn link(b: *std.Build, exe: *std.build.LibExeObjStep) void {
    const target = exe.target;
    const optimize = exe.optimize;

    const lib = buildC(b, target, optimize);
    exe.linkLibrary(lib);

    exe.linkLibC();
    exe.addIncludePath(.{ .path = root() ++ "/libsoundio"});

    if (target.isWindows()) {
        exe.linkSystemLibrary("ole32");
    } else if (target.isDarwin()) {
        const framework_path = getFrameworkPath(b.allocator);
        defer b.allocator.free(framework_path);

        exe.addFrameworkPath(.{ .path = framework_path });

        exe.linkFramework("CoreFoundation");
        exe.linkFramework("CoreAudio");
        exe.linkFramework("AudioUnit");
    } else {
        std.debug.panic("unsupported target {}", .{target});
    }

    exe.step.dependOn(&lib.step);
}

/// Build libsoundio C library.
fn buildC(b: *std.Build, target: std.zig.CrossTarget, optimize: std.builtin.Mode) *std.build.LibExeObjStep {
    const cflags = [_][]const u8{
        "-std=c11",
        "-fvisibility=hidden",
        "-Wall",
        "-Werror=strict-prototypes",
        "-Werror=old-style-definition",
        "-Werror=missing-prototypes",
        "-D_REENTRANT",
        "-D_POSIX_C_SOURCE=200809L",
        "-Wno-missing-braces",
        "-Werror",
        "-pedantic",
        "-Wno-deprecated-declarations",
        "-Wno-unused-variable",
        "-Wno-unused-but-set-variable",
    };
    const csources = [_][]const u8{
        root() ++ "/libsoundio/src/soundio.c",
        root() ++ "/libsoundio/src/util.c",
        root() ++ "/libsoundio/src/os.c",
        root() ++ "/libsoundio/src/dummy.c",
        root() ++ "/libsoundio/src/channel_layout.c",
        root() ++ "/libsoundio/src/ring_buffer.c",
    };

    const lib = b.addStaticLibrary(.{
        .name = "soundio",
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC();
    lib.addIncludePath(.{ .path = root() ++ "/libsoundio"});
    lib.addIncludePath(.{ .path = root() ++ "/libsoundio/src"});
    lib.addCSourceFiles(&csources, &cflags);

    lib.defineCMacro("ZIG_BUILD", null);
    lib.defineCMacro("SOUNDIO_VERSION_MAJOR", "2");
    lib.defineCMacro("SOUNDIO_VERSION_MINOR", "0");
    lib.defineCMacro("SOUNDIO_VERSION_PATCH", "0");
    lib.defineCMacro("SOUNDIO_VERSION_STRING", "\"2.0.0\"");

    if (target.isWindows()) {
        lib.defineCMacro("SOUNDIO_HAVE_WASAPI", null);
        lib.addCSourceFile(.{
            .file = .{ .path = root() ++ "/libsoundio/src/wasapi.c" },
            .flags = &cflags });
    } else if (target.isDarwin()) {
        const framework_path = getFrameworkPath(b.allocator);
        defer b.allocator.free(framework_path);
        lib.addFrameworkPath(.{ .path = framework_path});
        lib.defineCMacro("SOUNDIO_HAVE_COREAUDIO", null);
        lib.addCSourceFile(.{
            .file = .{ .path = root() ++ "/libsoundio/src/coreaudio.c" },
            .flags = &cflags });
    } else {
        std.debug.panic("unsupported target: only Windows and macOS currently supported", .{});
    }

    b.installArtifact(lib);
    return lib;
}

/// Get macOS framework path.
fn getFrameworkPath(alloc: std.mem.Allocator) []const u8 {
    var result = std.ChildProcess.exec(.{
        .allocator = alloc,
        .argv = &[_][]const u8{ "xcrun", "--show-sdk-path" },
    }) catch std.debug.panic("Failed to query macOS SDK path: couldn't exec process", .{});
    defer alloc.free(result.stdout);
    defer alloc.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) {
            std.debug.panic("Failed to query macOS SDK path: exit code {}", .{code});
        },
        else => std.debug.panic("Failed to query macOS SDK path: process exited abnormally", .{}),
    }

    const sdk_path = std.mem.trim(u8, result.stdout, "\n ");
    return std.mem.join(
        alloc,
        "/",
        &[_][]const u8{ sdk_path, "System/Library/Frameworks" },
    ) catch std.debug.panic("Out of memory", .{});
}

/// Build demos.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //const wav_mod = b.dependency("wav", .{ .target = target, .optimize = optimize }).module("wav");
    const soundio_mod = module(b);

    const demo = b.addExecutable(.{
        .name = "demo",
        .root_source_file = .{ .path = "demo.zig" },
        .target = target,
        .optimize = optimize,
    });
    demo.addModule("soundio", soundio_mod);
    link(b, demo);
    b.installArtifact(demo);

    const cmd = b.addRunArtifact(demo);
    cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        cmd.addArgs(args);
    }

    const step = b.step("run", "Run demo");
    step.dependOn(&cmd.step);
}
