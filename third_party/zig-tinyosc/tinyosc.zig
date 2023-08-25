const std = @import("std");
pub const c = @cImport({
    @cInclude("tinyosc.h");
});

pub fn getNextFloat(osc: *c.tosc_message) f32 {
    return c.tosc_getNextFloat(osc);
}

pub fn getNextInt32(osc: *c.tosc_message) i32 {
    return c.getNextInt32(osc);
}

pub fn getNextString(osc: *c.tosc_message) []const u8 {
    return std.mem.sliceTo(c.tosc_getNextString(osc), 0);
}
