const std = @import("std");
const math = @import("math.zig");

pub const Error = error{
    ParamNotFound,
};

// TODO: add more attributes as needed (e.g., warp, delta/rounding, scaling, smoothing, ...)
pub const Param = struct {
    name: []const u8,
    id: u16,
    value: f32,
    min: f32,
    max: f32,
};

pub fn create_param(allocator: std.mem.Allocator, name: []const u8, id: u16) !*Param {
    const param = try allocator.create(Param);
    param.* = .{
        .name = name,
        .id = id,
        .value = 0.0,
        .min = -1024.0, // TODO: decide on sensible default
        .max = 1024.0, // TODO: decide on sensible default
    };
    return param;
}

pub fn destroy_param(param: *Param, allocator: std.mem.Allocator) void {
    allocator.destroy(param);
}

pub fn set_param_min(param: *Param, min: f32) void {
    param.min = min;
}

pub fn set_param_max(param: *Param, max: f32) void {
    param.max = max;
}

pub fn set_param_value(param: *Param, value: f32) void {
    param.value = math.clipf(value, param.min, param.max);
}

fn Params(comptime T: type) type {
    return [@typeInfo(T).Enum.fields.len]*Param;
}

pub fn create_params(allocator: std.mem.Allocator, comptime T: type) !Params(T) {
    const fields = @typeInfo(T).Enum.fields;
    var params: [fields.len]*Param = undefined;
    inline for (0..fields.len) |i| {
        params[i] = try create_param(allocator, fields[i].name, i);
    }
    return params;
}

pub fn destroy_params(params: []*Param, allocator: std.mem.Allocator) void {
    for (params) |param| {
        destroy_param(param, allocator);
    }
}

pub fn get_param_from_params_by_id(params: []*Param, id: u16) !*Param {
    for (params) |param| {
        if (param.id == id) {
            return param;
        }
    }
    return Error.ParamNotFound;
}

pub fn get_param_from_params_by_name(params: []*Param, name: []const u8) !*Param {
    for (params) |param| {
        if (std.mem.eql(u8, param.name, name)) {
            return param;
        }
    }
    return Error.ParamNotFound;
}

pub const ParamsInfo = struct {
    params: []*Param,
};

test "params" {
    const allocator = std.testing.allocator;
    const MyParams = enum { first_param, second_param };

    var my_params = try create_params(allocator, MyParams);

    destroy_params(&my_params, allocator);
}
