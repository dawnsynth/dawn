const std = @import("std");
const expect = std.testing.expect;

const dawn = @import("../main.zig");

pub const Inputs = enum {
    in,
};

pub const Outputs = enum {
    out,
};

pub const Params = enum {
    c0,
    c1,
    c2,
    c3,
    c4,
    c5,
};

pub const Module = struct {
    pub const Self = @This();

    inputs: [@typeInfo(Inputs).Enum.fields.len]*dawn.Port,
    outputs: [@typeInfo(Outputs).Enum.fields.len]*dawn.Port,
    params: [@typeInfo(Params).Enum.fields.len]*dawn.Param,
    patch: *dawn.Patch,

    pub fn create(allocator: std.mem.Allocator, patch: *dawn.Patch) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .inputs = try dawn.create_ports(allocator, Inputs),
            .outputs = try dawn.create_ports(allocator, Outputs),
            .params = try dawn.create_params(allocator, Params),
            .patch = patch,
        };

        dawn.params.set_param_value(self.params[@intFromEnum(Params.c0)], 0.0);
        dawn.params.set_param_value(self.params[@intFromEnum(Params.c1)], 1.0);
        dawn.params.set_param_value(self.params[@intFromEnum(Params.c2)], 0.0);
        dawn.params.set_param_value(self.params[@intFromEnum(Params.c3)], 0.0);
        dawn.params.set_param_value(self.params[@intFromEnum(Params.c4)], 0.0);
        dawn.params.set_param_value(self.params[@intFromEnum(Params.c5)], 0.0);

        return self;
    }

    pub fn tick(self: *Self) !void {
        // TODO: more coefficients
        if (self.outputs[@intFromEnum(Outputs.out)].num_connected > 0) {
            var coeff = [_]f32{ self.params[@intFromEnum(Params.c0)].value, self.params[@intFromEnum(Params.c1)].value, self.params[@intFromEnum(Params.c2)].value, self.params[@intFromEnum(Params.c3)].value, self.params[@intFromEnum(Params.c4)].value, self.params[@intFromEnum(Params.c5)].value };
            self.outputs[@intFromEnum(Outputs.out)].value = dawn.math.chebval(self.inputs[@intFromEnum(Inputs.in)].value, &coeff);
        }
    }
};
