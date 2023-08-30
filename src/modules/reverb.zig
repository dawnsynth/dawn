const std = @import("std");
const dawn = @import("../main.zig");

pub const Inputs = enum {
    in,
};

pub const Outputs = enum {
    out,
};

pub const Params = enum {
    gain, // TODO: Make gain do sth
};

pub const Module = struct {
    pub const Self = @This();

    inputs: [@typeInfo(Inputs).Enum.fields.len]*dawn.Port,
    outputs: [@typeInfo(Outputs).Enum.fields.len]*dawn.Port,
    params: [@typeInfo(Params).Enum.fields.len]*dawn.Param,
    patch: *dawn.Patch,

    ap1: *dawn.dsp.AllPass(f32, 142),
    ap2: *dawn.dsp.AllPass(f32, 379),
    ap3: *dawn.dsp.AllPass(f32, 107),
    ap4: *dawn.dsp.AllPass(f32, 277),
    ap5: *dawn.dsp.AllPass(f32, 1800),
    ap6: *dawn.dsp.AllPass(f32, 908),
    ap7: *dawn.dsp.AllPass(f32, 2656),

    delay1: *dawn.dsp.Delay(f32, 4453),
    delay2: *dawn.dsp.Delay(f32, 3163),

    pub fn create(allocator: std.mem.Allocator, patch: *dawn.Patch) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .inputs = try dawn.create_ports(allocator, Inputs),
            .outputs = try dawn.create_ports(allocator, Outputs),
            .params = try dawn.create_params(allocator, Params),
            .patch = patch,
            .ap1 = try dawn.dsp.AllPass(f32, 142).create(allocator), // TODO: Avoid specifying lengths twice
            .ap2 = try dawn.dsp.AllPass(f32, 379).create(allocator),
            .ap3 = try dawn.dsp.AllPass(f32, 107).create(allocator),
            .ap4 = try dawn.dsp.AllPass(f32, 277).create(allocator),
            .ap5 = try dawn.dsp.AllPass(f32, 1800).create(allocator),
            .ap6 = try dawn.dsp.AllPass(f32, 908).create(allocator),
            .ap7 = try dawn.dsp.AllPass(f32, 2656).create(allocator),
            .delay1 = try dawn.dsp.Delay(f32, 4453).create(allocator),
            .delay2 = try dawn.dsp.Delay(f32, 3163).create(allocator),
        };

        dawn.params.set_param_value(self.params[@intFromEnum(Params.gain)], 1.0);

        return self;
    }

    pub fn destroy_hook(self: *Self, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.delay1.destroy();
    }

    pub fn tick(self: *Self) !void {
        if (self.outputs[@intFromEnum(Outputs.out)].num_connected > 0) {
            var res = self.inputs[@intFromEnum(Inputs.in)].value;
            res = self.ap1.tick(res);
            res = self.ap2.tick(res);
            res = self.ap3.tick(res);
            res = self.ap4.tick(res);
            res = self.ap5.tick(res);
            res = self.delay1.tick(res);
            res = self.ap6.tick(res);
            res = self.ap7.tick(res);
            res = self.delay2.tick(res);
            self.outputs[@intFromEnum(Outputs.out)].value = res;
        }
    }
};
