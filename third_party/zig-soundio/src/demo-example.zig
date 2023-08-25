/// The example from the README.
const std = @import("std");
const soundio = @import("soundio");

const sample_rate: usize = 44100;

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
    std.time.sleep(10 * 1000 * 1000 * 1000); // Sleep for 10 secs.
}

var phase: f32 = 0.0;
/// soundio will call this function to render sound. Your job is to fill `buffer` with `num_frames` frames.
fn callback(arg: ?*anyopaque, num_frames: usize, buffer: *soundio.Buffer) void {
    _ = arg;

    const freq: f32 = 261.63; // Middle C.
    const sample_rate: f32 = @intToFloat(sample_rate);
    const amplitude: f32 = 0.4; // Not too loud.

    var frame: usize = 0;
    while (frame < num_frames) : (frame += 1) {
        const val = amplitude * (2.0 * std.math.fabs(2.0 * phase - 1.0) - 1);
        buffer.channels[0].set(frame, val);
        buffer.channels[1].set(frame, val);

        phase += freq / sample_rate_f;
        if (phase >= 1.0)
            phase -= 1.0;
    }
}
