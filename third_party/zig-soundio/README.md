# zig-soundio

Zig wrapper for libsoundio cross-platform audio library. Add sound to your Zig application!

Disclaimer: this project is experimental and evolving. It isn't meant to be full featured or well designed. It's just what works for
me now.


## Usage

### Building

`zig-soundio` may require a recent nightly build of Zig.

The following will build and link the C library and add the Zig module to your project.

1. Clone `zig-soundio` via `git clone --recurse https://github.com/veloscillator/zig-soundio.git`.

2. Add to your build.zig:

```zig
const std = @import("std");
const soundio = @import("path/to/zig-soundio/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Define your executable...
    const exe = b.addExecutable(.{
        .name = "cat_simulator2000",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // ... add zig-soundio module...
    exe.addModule("soundio", soundio.module(b));

    // ... and link the C library!
    soundio.link(b, exe);

    exe.install();
    
    // etc.
}
```

### Example

I've read so many sine waves, so we're doing a triangle wav:

```zig
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
    const sample_rate_f = @intToFloat(f32, sample_rate);
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
```


### Demos

```bash
zig build demo-example                # Run the example above.
zig build demo-phase                  # Play phased saw waves.
zig build demo-wav -- my/favorite.wav # Play a wav file using zig-wav.
```


## Limitations

- Only macOS and Windows are supported.
- Only a subset of the libsoundio API is added. Currently, typical sound output scenarios are supported.
