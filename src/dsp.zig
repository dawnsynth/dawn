const std = @import("std");

pub fn Delay(comptime T: type, comptime length: usize) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        buffer: [length + 1]T,
        pos: usize,

        pub fn create(allocator: std.mem.Allocator) !*Self {
            const self = try allocator.create(Self);
            self.allocator = allocator;
            self.buffer = std.mem.zeroes([length + 1]T);
            self.pos = 0;
            return self;
        }

        pub fn destroy(self: *Self) void {
            self.allocator.destroy(self);
        }

        pub fn tick(self: *Self, x: T) T {
            self.buffer[self.pos] = x;
            self.pos = (self.pos + self.buffer.len - 1) % (self.buffer.len);
            return self.buffer[self.pos];
        }
    };
}

test "delay" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var delay1 = try Delay(u32, 1).create(allocator);
    defer delay1.destroy();
    try std.testing.expect(delay1.pos == 0);
    try std.testing.expect(delay1.tick(1) == 0);
    try std.testing.expect(delay1.tick(2) == 1);
    try std.testing.expect(delay1.tick(3) == 2);

    var delay2 = try Delay(u32, 2).create(allocator);
    defer delay2.destroy();
    try std.testing.expect(delay2.tick(1) == 0);
    try std.testing.expect(delay2.tick(2) == 0);
    try std.testing.expect(delay2.tick(3) == 1);
}

pub fn AllPass(comptime T: type, comptime length: usize) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        buffer: [length + 1]T,
        write_pos: usize,
        read_pos: usize,

        pub fn create(allocator: std.mem.Allocator) !*Self {
            const self = try allocator.create(Self);
            self.allocator = allocator;
            self.buffer = std.mem.zeroes([length + 1]T);
            self.write_pos = 0;
            self.read_pos = 0;
            return self;
        }

        pub fn destroy(self: *Self) void {
            self.allocator.destroy(self);
        }

        pub fn tick(self: *Self, x: T) T {
            self.read_pos = (self.write_pos + self.buffer.len - 1) % (self.buffer.len);
            self.buffer[self.write_pos] = x - 0.5 * self.buffer[self.read_pos];
            const res = 0.5 * self.buffer[self.write_pos] + self.buffer[self.read_pos];
            self.write_pos = self.read_pos;
            return res;
        }
    };
}

test "allpass" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ap1 = try AllPass(f32, 2).create(allocator);
    defer ap1.destroy();
    try std.testing.expect(ap1.read_pos == 0);
    try std.testing.expect(ap1.write_pos == 0);

    try std.testing.expect(ap1.tick(0.0) == 0.0);
    try std.testing.expect(ap1.tick(1.0) == 0.5);
    try std.testing.expect(ap1.tick(2.0) == 1.0);
}
