/// Output saw wave with different phase on L and R channels.
const std = @import("std");
const soundio = @import("soundio");

// Naive sawtooth oscillator.
const Saw = struct {
    sample_rate: f32,
    freq: f32,
    phase: f32 = 0.0,

    fn next(self: *Saw) f32 {
        const value = 2.0 * self.phase - 1.0;
        self.phase += self.freq / self.sample_rate;
        if (self.phase >= 1.0) {
            self.phase -= 1.0;
        }
        return value;
    }
};

const sample_rate: usize = 48000;
const sample_rate_f: f32 = @floatFromInt(sample_rate);

var saw_l = Saw{ .sample_rate = sample_rate_f, .freq = 128.813, .phase = 0.0 };
var saw_r = Saw{ .sample_rate = sample_rate_f, .freq = 130.813, .phase = 1.2 };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var sound = try soundio.SoundIo.init();
    defer sound.deinit();

    var outstream = try sound.createOutputStream(alloc, .{
        .sample_rate = sample_rate,
        .channel_layout = .stereo,
        .write_callback = callback,
        .arg = null,
    });
    defer outstream.deinit();

    try outstream.start();

    _ = try std.io.getStdOut().writer().print("Press enter to exit\n", .{});
    _ = try std.io.getStdIn().reader().readByte();
}

fn callback(arg: ?*anyopaque, num_frames: usize, buffer: *soundio.Buffer) void {
    _ = arg;
    const amplitude: f32 = 0.25;
    var frame: usize = 0;
    while (frame < num_frames) : (frame += 1) {
        buffer.channels[0].set(frame, amplitude * saw_l.next()); // Left.
        buffer.channels[1].set(frame, amplitude * saw_r.next()); // Right.
    }
}
