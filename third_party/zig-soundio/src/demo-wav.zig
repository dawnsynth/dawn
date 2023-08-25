/// Play a wav file.
const std = @import("std");
const soundio = @import("soundio");
const wav = @import("wav");

const DecoderType = wav.Decoder(std.io.BufferedReader(4096, std.fs.File.Reader).Reader);

var done: std.Thread.Semaphore = .{};
var is_done = false;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var sound = try soundio.SoundIo.init();
    defer sound.deinit();

    var args = try std.process.argsAlloc(alloc);
    defer alloc.free(args);

    if (args.len != 2) {
        try stdout.print("usage: zig build demo-wav -- <path/to/file.wav>", .{});
        std.process.exit(1);
    }

    var file = try std.fs.cwd().openFile(args[1], .{});
    defer file.close();

    var reader = std.io.bufferedReader(file.reader());
    var decoder = try wav.decoder(reader.reader());
    comptime std.debug.assert(@TypeOf(decoder) == DecoderType);

    var outstream = try sound.createOutputStream(alloc, .{
        .sample_rate = decoder.sampleRate(),
        .channel_layout = switch (decoder.channels()) {
            1 => .mono,
            2 => .stereo,
            else => std.debug.panic("only two channels, please", .{}),
        },
        .write_callback = callback,
        .arg = &decoder,
    });
    defer outstream.deinit();

    try outstream.start();
    done.wait();
}

fn callback(arg: ?*anyopaque, num_frames: usize, dest: *soundio.Buffer) void {
    if (is_done)
        return; // Prevent race with decoder destroy.

    std.debug.assert(arg != null);
    var decoder: *DecoderType = @ptrCast(@alignCast(arg.?));
    const num_channels = decoder.channels(); // Already checked against output channels.

    var src: [128]f32 = undefined;
    var frame: usize = 0;
    while (frame < num_frames) {
        const samples_to_read = std.math.min((num_frames - frame) * num_channels, src.len);
        const samples_read = decoder.read(
            f32,
            src[0..samples_to_read],
        ) catch |err| std.debug.panic("failed to read from wav: {}", .{err});

        std.debug.assert(samples_read % num_channels == 0); // zig-wav considers this malformed.
        const frames_read = samples_read / num_channels;

        var i: usize = 0;
        while (i < frames_read) : (i += 1) {
            var chan: usize = 0;
            while (chan < num_channels) : (chan += 1) {
                dest.channels[chan].set(frame + i, src[i * num_channels + chan]);
            }
        }
        frame += frames_read;
        if (samples_read < samples_to_read) {
            dest.zero(frame);
            is_done = true;
            done.post();
            break;
        }
    }
}
