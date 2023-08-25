const std = @import("std");
const dawn = @import("../main.zig");

pub const Inputs = enum {
    freq_mod, // TODO: make this input affect the output
};

pub const Outputs = enum {
    out,
};

pub const Params = enum {
    freq,
};

pub const Module = struct {
    pub const Self = @This();

    inputs: [@typeInfo(Inputs).Enum.fields.len]*dawn.Port,
    outputs: [@typeInfo(Outputs).Enum.fields.len]*dawn.Port,
    params: [@typeInfo(Params).Enum.fields.len]*dawn.Param,
    patch: *dawn.Patch,

    phasor: f32,

    pub fn create(allocator: std.mem.Allocator, patch: *dawn.Patch) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .inputs = try dawn.create_ports(allocator, Inputs),
            .outputs = try dawn.create_ports(allocator, Outputs),
            .params = try dawn.create_params(allocator, Params),
            .patch = patch,
            .phasor = 0.0,
        };

        dawn.params.set_param_min(self.params[@intFromEnum(Params.freq)], 0.0);
        dawn.params.set_param_max(self.params[@intFromEnum(Params.freq)], 20_000.0);
        dawn.params.set_param_value(self.params[@intFromEnum(Params.freq)], 440.0);

        return self;
    }

    pub fn tick(self: *Self) !void {
        // TODO: table-lookup
        if (self.outputs[@intFromEnum(Outputs.out)].num_connected > 0) {
            self.outputs[@intFromEnum(Outputs.out)].value = 0.5 * std.math.sin(self.phasor);
            self.phasor += ((2.0 * std.math.pi * self.params[@intFromEnum(Params.freq)].value) /
                (self.patch.sampling_rate));
            if (self.phasor > (2.0 * std.math.pi)) {
                self.phasor -= (2.0 * std.math.pi);
            }
        }
    }
};
