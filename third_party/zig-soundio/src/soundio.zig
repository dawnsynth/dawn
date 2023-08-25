const std = @import("std");
const c = @cImport({
    @cInclude("soundio/soundio.h");
});

pub const Error = error{
    OutOfMemory,
    InitAudioBackend,
    SystemResources,
    OpeningDevice,
    NoSuchDevice,
    Invalid,
    BackendUnavailable,
    Streaming,
    IncompatibleDevice,
    NoSuchClient,
    IncompatibleBackend,
    BackendDisconnected,
    Interrupted,
    Underflow,
    EncodingString,
};

pub const ChannelLayout = enum {
    mono,
    stereo,
};

pub const Channel = struct {
    data: []f32,
    step: usize,

    pub fn set(self: *Channel, index: usize, value: f32) void {
        self.data[index * self.step] = value;
    }

    pub fn zero(self: *Channel, start_index: usize) void {
        var i: usize = start_index * self.step;
        while (i < self.data.len) : (i += self.step) {
            self.data[i] = 0.0;
        }
    }
};

pub const Buffer = struct {
    channels: []Channel,

    pub fn zero(self: *Buffer, start_index: usize) void {
        for (self.channels) |*channel| {
            channel.zero(start_index);
        }
    }
};

pub const WriteCallback = *const fn (arg: ?*anyopaque, num_frames: usize, buffer: *Buffer) void;

pub const OutputStreamOptions = struct {
    device_index: ?usize = null,
    sample_rate: usize = 48000,
    channel_layout: ChannelLayout = .stereo,
    write_callback: WriteCallback,
    arg: ?*anyopaque = null,
};

pub const SoundIo = struct {
    ptr: [*c]c.SoundIo,

    pub fn init() Error!SoundIo {
        const ptr = c.soundio_create();
        if (ptr == null)
            return error.OutOfMemory;
        errdefer c.soundio_destroy(ptr);

        try check(c.soundio_connect(ptr));
        c.soundio_flush_events(ptr);

        return SoundIo{ .ptr = ptr };
    }

    pub fn deinit(self: *SoundIo) void {
        c.soundio_destroy(self.ptr);
    }

    pub fn default_output_device_index(self: *SoundIo) Error!usize {
        const index = c.soundio_default_output_device_index(self.ptr);
        if (index < 0)
            return error.NoSuchDevice;
        return @as(usize, @intCast(index));
    }

    pub fn createOutputStream(self: *SoundIo, alloc: std.mem.Allocator, options: OutputStreamOptions) Error!*OutputStream {
        const index = if (options.device_index) |i| i else try self.default_output_device_index();
        const device = c.soundio_get_output_device(self.ptr, @as(c_int, @intCast(index)));
        if (device == null)
            return error.NoSuchDevice;
        errdefer c.soundio_device_unref(device);

        var ptr = c.soundio_outstream_create(device);
        if (ptr == null)
            return error.OutOfMemory;
        errdefer c.soundio_outstream_destroy(ptr);

        var outstream = try alloc.create(OutputStream);
        errdefer alloc.destroy(outstream);

        outstream.ptr = ptr;
        outstream.device = device;
        outstream.write_callback = options.write_callback;
        outstream.arg = options.arg;
        outstream.alloc = alloc;

        try outstream.init(options);
        return outstream;
    }
};

pub const OutputStream = struct {
    ptr: [*c]c.SoundIoOutStream,
    device: [*c]c.SoundIoDevice,
    write_callback: WriteCallback,
    arg: ?*anyopaque,
    alloc: std.mem.Allocator,

    fn init(self: *OutputStream, options: OutputStreamOptions) Error!void {
        self.ptr.*.write_callback = dispatchWriteCallback;
        self.ptr.*.userdata = self;
        self.ptr.*.format = c.SoundIoFormatFloat32NE;
        self.ptr.*.layout = switch (options.channel_layout) {
            .mono => c.soundio_channel_layout_get_builtin(c.SoundIoChannelLayoutIdMono).*,
            .stereo => c.soundio_channel_layout_get_builtin(c.SoundIoChannelLayoutIdStereo).*,
        };
        self.ptr.*.sample_rate = @as(c_int, @intCast(options.sample_rate));

        try check(c.soundio_outstream_open(self.ptr));
        try check(self.ptr.*.layout_error);
    }

    pub fn deinit(self: *OutputStream) void {
        c.soundio_outstream_destroy(self.ptr);
        c.soundio_device_unref(self.device);
        self.alloc.destroy(self);
    }

    pub fn start(self: *OutputStream) !void {
        try check(c.soundio_outstream_start(self.ptr));
    }

    fn writeCallback(self: *OutputStream, frame_count_min: c_int, frame_count_max: c_int) void {
        _ = frame_count_min;

        const num_channels = @as(usize, @intCast(self.ptr.*.layout.channel_count));
        var channels: [2]Channel = undefined;
        var buffer = Buffer{ .channels = channels[0..num_channels] };

        var areas: [*c]c.SoundIoChannelArea = null;
        var frames_left = frame_count_max;
        var frame_count = frame_count_max;
        while (frames_left > 0) : (frames_left -= frame_count) {
            check(c.soundio_outstream_begin_write(self.ptr, &areas, &frame_count)) catch |err|
                std.debug.panic("soundio_outstream_begin_write error: {}", .{err});
            if (frame_count <= 0)
                break;

            var i: usize = 0;
            while (i < num_channels) : (i += 1) {
                const step = @as(usize, @intCast(areas[i].step)) / 4;
                channels[i].step = step;
                channels[i].data = @as(
                    [*]f32,
                    @ptrCast(@alignCast(areas[i].ptr)),
                )[0..(@as(usize, @intCast(frame_count)) * step)];
            }

            self.write_callback(self.arg, @as(usize, @intCast(frame_count)), &buffer);
            check(c.soundio_outstream_end_write(self.ptr)) catch |err|
                std.debug.panic("soundio_oustream_end_write error: {}", .{err});
        }
    }
};

export fn dispatchWriteCallback(outstream: [*c]c.SoundIoOutStream, frame_count_min: c_int, frame_count_max: c_int) callconv(.C) void {
    var self = @as(*OutputStream, @ptrCast(@alignCast(outstream.*.userdata)));
    self.writeCallback(frame_count_min, frame_count_max);
}

fn convertError(err: c_int) ?Error {
    return switch (err) {
        c.SoundIoErrorNoMem => error.OutOfMemory,
        c.SoundIoErrorInitAudioBackend => error.InitAudioBackend,
        c.SoundIoErrorSystemResources => error.SystemResources,
        c.SoundIoErrorOpeningDevice => error.OpeningDevice,
        c.SoundIoErrorNoSuchDevice => error.NoSuchDevice,
        c.SoundIoErrorInvalid => error.Invalid,
        c.SoundIoErrorBackendUnavailable => error.BackendUnavailable,
        c.SoundIoErrorStreaming => error.Streaming,
        c.SoundIoErrorIncompatibleDevice => error.IncompatibleDevice,
        c.SoundIoErrorNoSuchClient => error.NoSuchClient,
        c.SoundIoErrorIncompatibleBackend => error.IncompatibleBackend,
        c.SoundIoErrorBackendDisconnected => error.BackendDisconnected,
        c.SoundIoErrorInterrupted => error.Interrupted,
        c.SoundIoErrorUnderflow => error.Underflow,
        c.SoundIoErrorEncodingString => error.EncodingString,
        else => null,
    };
}

fn check(err: c_int) Error!void {
    if (convertError(err)) |e|
        return e;
}
