const std = @import("std");
const tinyosc = @import("tinyosc");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var buffer: [1024]u8 = undefined;

pub fn main() !void {
    const num1: f32 = 1.0; // 1.0 does not work; 10.0 works;
    var len = tinyosc.c.tosc_writeMessage(&buffer, @sizeOf(@TypeOf(buffer)), "/address", "f", num1);

    var msg: *tinyosc.c.tosc_message = try allocator.create(tinyosc.c.tosc_message);
    _ = tinyosc.c.tosc_parseMessage(msg, &buffer, @intCast(len));

    const num1_readout: f32 = tinyosc.c.tosc_getNextFloat(msg);
    std.debug.print("num1_readout: {any}\n", .{ num1_readout });
}