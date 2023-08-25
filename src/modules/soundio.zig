const std = @import("std");
const dawn = @import("../main.zig");
const soundio = @import("soundio");

pub const Inputs = enum {
    chan_1,
    chan_2,
};

// TODO: expose audio inputs as module Outputs

pub const Module = struct {
    pub const Self = @This();

    inputs: [@typeInfo(Inputs).Enum.fields.len]*dawn.Port,
    patch: *dawn.Patch,

    sound: *soundio.SoundIo,
    outstream: *soundio.OutputStream,

    pub fn create(allocator: std.mem.Allocator, patch: *dawn.Patch) !*Self {
        if (patch.interface != null) {
            return dawn.Error.PatchHasInterface;
        }

        var sound = try soundio.SoundIo.init();
        var outstream = try sound.createOutputStream(allocator, .{
            .sample_rate = @intFromFloat(patch.sampling_rate),
            .channel_layout = .stereo, // TODO: allow more flexiblity
            .write_callback = callback,
            .arg = patch,
        });

        const self = try allocator.create(Self);
        self.* = .{
            .inputs = try dawn.create_ports(allocator, Inputs),
            .patch = patch,
            .sound = &sound,
            .outstream = outstream,
        };
        patch.interface = self;

        try outstream.start();

        return self;
    }

    pub fn destroy_hook(self: *Self, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.outstream.deinit();
        self.sound.deinit();
        self.patch.interface = null;
    }

    pub fn tick(self: *Self) !void {
        _ = self;
    }
};

fn callback(arg: ?*anyopaque, num_frames: usize, buffer: *soundio.Buffer) void {
    const patch: *dawn.Patch = @ptrCast(@alignCast(arg));
    const interface: *Module = @ptrCast(@alignCast(patch.interface));

    var frame: usize = 0;
    while (frame < num_frames) : (frame += 1) {
        patch.tick() catch |err| {
            err catch {};
            // TODO: consider better error handling in callback
            //std.debug.print("error occurred during tick {any}", .{ err });
        };

        if (interface.inputs[@intFromEnum(Inputs.chan_1)].num_connected == 1 and interface.inputs[@intFromEnum(Inputs.chan_2)].num_connected == 0) {
            // normalling; chan_1 used for stereo
            var val = interface.inputs[@intFromEnum(Inputs.chan_1)].value;
            if (!std.math.isNan(val)) {
                buffer.channels[0].set(frame, dawn.math.clipf(val, -1.0, 1.0));
                buffer.channels[1].set(frame, dawn.math.clipf(val, -1.0, 1.0));
            }
        } else if (interface.inputs[@intFromEnum(Inputs.chan_1)].num_connected == 0 and interface.inputs[@intFromEnum(Inputs.chan_2)].num_connected == 1) {
            // normalling; chan_2 used for stereo
            var val = interface.inputs[@intFromEnum(Inputs.chan_2)].value;
            if (!std.math.isNan(val)) {
                buffer.channels[0].set(frame, dawn.math.clipf(val, -1.0, 1.0));
                buffer.channels[1].set(frame, dawn.math.clipf(val, -1.0, 1.0));
            }
        } else if (interface.inputs[@intFromEnum(Inputs.chan_1)].num_connected == 1 and interface.inputs[@intFromEnum(Inputs.chan_2)].num_connected == 1) {
            // signal on both
            var val_1 = interface.inputs[@intFromEnum(Inputs.chan_1)].value;
            var val_2 = interface.inputs[@intFromEnum(Inputs.chan_2)].value;
            if (!std.math.isNan(val_1)) {
                buffer.channels[0].set(frame, dawn.math.clipf(val_1, -1.0, 1.0));
            }
            if (!std.math.isNan(val_2)) {
                buffer.channels[1].set(frame, dawn.math.clipf(val_2, -1.0, 1.0));
            }
        } else {
            // no sound
            buffer.channels[0].set(frame, 0.0);
            buffer.channels[1].set(frame, 0.0);
        }

        // TODO: add functionality for easy logging of outputs
    }
}
