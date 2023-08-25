pub const version = "0.0.1";

const std = @import("std");

pub const connections = @import("connections.zig");
pub const Port = connections.Port;
pub const Cable = connections.Cable;
pub const create_ports = connections.create_ports;

pub const params = @import("params.zig");
pub const Param = params.Param;
pub const create_params = params.create_params;

pub const math = @import("math.zig");

pub const Error = connections.Error || params.Error || error{ ModuleTypeUnknown, ModuleNameInvalid, ModuleNameTaken, ModuleRemovalFailed, ModuleNotFound, ModuleHasNoParams, CableExists, CableRemovalFailed, PatchHasInterface };

pub const Module = union(enum) {
    // available modules:
    chebshaper: *@import("modules/chebshaper.zig").Module,
    opensoundcontrol: *@import("modules/opensoundcontrol.zig").Module,
    sineosc: *@import("modules/sineosc.zig").Module,
    soundio: *@import("modules/soundio.zig").Module,

    pub fn create(allocator: std.mem.Allocator, module_type: []const u8, patch: *Patch) !*Module {
        inline for (std.meta.fields(@This())) |field| {
            if (std.mem.eql(u8, module_type, field.name)) {
                const load = try @typeInfo(field.type).Pointer.child.create(allocator, patch);
                const new_module = try allocator.create(Module);
                new_module.* = @unionInit(Module, field.name, load);
                return new_module;
            }
        }
        return Error.ModuleTypeUnknown;
    }

    pub fn destroy(self: *Module, allocator: std.mem.Allocator) void {
        switch (self.*) {
            inline else => |m| {
                if (comptime std.meta.trait.hasFn("destroy_hook")(@TypeOf(m.*))) {
                    m.destroy_hook(allocator);
                }
                if (comptime std.meta.trait.hasField("inputs")(@TypeOf(m.*))) {
                    connections.destroy_ports(&m.inputs, allocator);
                }
                if (comptime std.meta.trait.hasField("outputs")(@TypeOf(m.*))) {
                    connections.destroy_ports(&m.outputs, allocator);
                }
                if (comptime std.meta.trait.hasField("params")(@TypeOf(m.*))) {
                    params.destroy_params(&m.params, allocator);
                }
                allocator.destroy(m);
            },
        }
        allocator.destroy(self);
    }

    pub fn getInputs(self: *Module) []*connections.Port {
        switch (self.*) {
            inline else => |m| {
                if (comptime std.meta.trait.hasField("inputs")(@TypeOf(m.*))) {
                    return &m.inputs;
                }
            },
        }
        return &.{};
    }

    pub fn getOutputs(self: *Module) []*connections.Port {
        switch (self.*) {
            inline else => |m| {
                if (comptime std.meta.trait.hasField("outputs")(@TypeOf(m.*))) {
                    return &m.outputs;
                }
            },
        }
        return &.{};
    }

    pub fn getParams(self: *Module) []*params.Param {
        switch (self.*) {
            inline else => |m| {
                if (comptime std.meta.trait.hasField("params")(@TypeOf(m.*))) {
                    return &m.params;
                }
            },
        }
        return &.{};
    }

    pub fn setParam(self: *Module, param_name: []const u8, value: f32) !void {
        switch (self.*) {
            inline else => |m| {
                if (comptime !std.meta.trait.hasField("params")(@TypeOf(m.*))) {
                    return Error.ModuleHasNoParams;
                }
                var param = try params.get_param_from_params_by_name(&m.params, param_name);
                params.set_param_value(param, value);
                // TODO: decide whether set_param_hook is needed; currently it is unused
                if (comptime std.meta.trait.hasFn("set_param_hook")(@TypeOf(m.*))) {
                    m.set_param_hook(param, value);
                }
            },
        }
    }

    pub fn tick(self: *Module) !void {
        switch (self.*) {
            inline else => |m| try m.tick(),
        }
    }
};

pub const Patch = struct {
    pub const Self = @This();

    allocator: std.mem.Allocator,
    modules: std.StringHashMap(*Module),
    cables: std.AutoHashMap(*connections.Cable, void),

    sampling_rate: f32 = 48000.0, // TODO: consider using uint32 instead
    interface: ?*anyopaque = null,
    num_steps: u32 = 0,

    port_receive: u16 = 2501,
    port_send: u16 = 2502,

    pub fn create(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .modules = std.StringHashMap(*Module).init(allocator),
            .cables = std.AutoHashMap(*connections.Cable, void).init(allocator),
        };
        return self;
    }

    pub fn destroy(self: *Self, allocator: std.mem.Allocator) void {
        var cable_iterator = self.cables.iterator();
        while (cable_iterator.next()) |c| {
            connections.destroy_cable(c.key_ptr.*, allocator);
        }
        self.cables.deinit();

        var module_iterator = self.modules.iterator();
        while (module_iterator.next()) |m| {
            m.value_ptr.*.destroy(allocator);
        }
        self.modules.deinit();

        allocator.destroy(self);
    }

    pub fn add_module(self: *Self, module_type: []const u8, module_name: []const u8) !void {
        if (std.mem.indexOf(u8, module_name, "/") != null) {
            return Error.ModuleNameInvalid;
        }
        if (self.modules.contains(module_name)) {
            return Error.ModuleNameTaken;
        }
        const new_module = try Module.create(self.allocator, module_type, self);
        try self.modules.put(module_name, new_module);
    }

    pub fn add_cable(self: *Self, src_module_name: []const u8, src_port_name: []const u8, dst_module_name: []const u8, dst_port_name: []const u8) !void {
        const src_module = self.modules.get(src_module_name) orelse return Error.ModuleNotFound;
        const dst_module = self.modules.get(dst_module_name) orelse return Error.ModuleNotFound;

        const src_port = try connections.get_port_from_ports_by_name(src_module.getOutputs(), src_port_name);
        const dst_port = try connections.get_port_from_ports_by_name(dst_module.getInputs(), dst_port_name);

        const new_cable = try connections.create_cable(self.allocator, src_port, dst_port, self.modules.getKeyPtr(src_module_name).?, self.modules.getKeyPtr(dst_module_name).?);

        if (self.cables.contains(new_cable)) {
            connections.destroy_cable(new_cable, self.allocator);
            return Error.CableExists;
        }

        try self.cables.put(new_cable, {});
    }

    pub fn remove_cable(self: *Self, cable: *connections.Cable) !void {
        cable.dst_port.value = 0;
        if (!self.cables.remove(cable)) {
            return Error.CableRemovalFailed;
        }
        connections.destroy_cable(cable, self.allocator);
    }

    pub fn remove_cable_by_names(self: *Self, src_module_name: []const u8, src_port_name: []const u8, dst_module_name: []const u8, dst_port_name: []const u8) !void {
        var cable_iterator = self.cables.iterator();
        while (cable_iterator.next()) |c| {
            if (std.mem.eql(u8, c.key_ptr.*.src_module_name.*, src_module_name) and std.mem.eql(u8, c.key_ptr.*.dst_module_name.*, dst_module_name) and std.mem.eql(u8, c.key_ptr.*.src_port.*.name, src_port_name) and std.mem.eql(u8, c.key_ptr.*.dst_port.*.name, dst_port_name)) {
                try self.remove_cable(c.key_ptr.*);
            }
        }
    }

    pub fn remove_all_cables(self: *Self) !void {
        var cable_iterator = self.cables.iterator();
        while (cable_iterator.next()) |c| {
            try self.remove_cable(c);
        }
    }

    pub fn remove_module(self: *Self, module_name: []const u8) !void {
        if (!self.modules.contains(module_name)) {
            return Error.ModuleNotFound;
        }

        var cable_iterator = self.cables.iterator();
        while (cable_iterator.next()) |c| {
            if (std.mem.eql(u8, c.key_ptr.*.src_module_name.*, module_name) or std.mem.eql(u8, c.key_ptr.*.dst_module_name.*, module_name)) {
                try self.remove_cable(c.key_ptr.*);
            }
        }

        const module = self.modules.get(module_name).?;
        if (!self.modules.remove(module_name)) {
            return Error.ModuleRemovalFailed;
        }
        module.destroy(self.allocator);
    }

    pub fn remove_all_modules(self: *Self) !void {
        var module_iterator = self.modules.iterator();
        while (module_iterator.next()) |m| {
            try self.remove_module(m.key_ptr.*);
        }
    }

    pub fn tick(self: *Self) !void {
        var module_iterator = self.modules.iterator();
        while (module_iterator.next()) |m| {
            try m.value_ptr.*.tick();
        }

        var cable_iterator = self.cables.iterator();
        while (cable_iterator.next()) |c| {
            c.key_ptr.*.dst_port.value = c.key_ptr.*.src_port.value;
        }

        self.num_steps += 1;
    }
};

pub const ModuleInfo = struct {
    module_name: []const u8,
    module_type: []const u8,
    params: params.ParamsInfo,
};

pub const PatchInfo = struct {
    modules: []const ModuleInfo,
    cables: []const connections.CableInfo,
};

pub fn create_patch_info(patch: *Patch, allocator: std.mem.Allocator) !PatchInfo {
    const cables_info = try connections.create_cables_info(&patch.cables, allocator);

    const modules_info = try allocator.alloc(ModuleInfo, patch.modules.count());
    var i: u32 = 0;
    var module_iterator = patch.modules.iterator();
    while (module_iterator.next()) |m| : (i += 1) {
        modules_info[i] = .{ .module_name = m.key_ptr.*, .module_type = @tagName(std.meta.activeTag(m.value_ptr.*.*)), .params = params.ParamsInfo{ .params = m.value_ptr.*.getParams() } };
    }

    return PatchInfo{ .cables = cables_info, .modules = modules_info };
}

pub fn destroy_patch_info(patch_info: PatchInfo, allocator: std.mem.Allocator) void {
    allocator.free(patch_info.cables);
    allocator.free(patch_info.modules);
}

pub fn create_patch_info_string(patch: *Patch, allocator: std.mem.Allocator) ![]const u8 {
    const patch_info = try create_patch_info(patch, allocator);
    defer destroy_patch_info(patch_info, allocator);
    return std.json.stringifyAlloc(allocator, patch_info, .{});
}

test "patch" {
    const allocator = std.testing.allocator;

    var patch = try Patch.create(allocator);
    try patch.add_module("sineosc", "osc");
    try patch.add_module("chebshaper", "cheb");
    try patch.add_cable("osc", "out", "cheb", "in");
    try patch.tick();

    const patch_info_str = try create_patch_info_string(patch, allocator);
    defer allocator.free(patch_info_str);

    try patch.remove_all_modules();

    const patch_info = try std.json.parseFromSlice(PatchInfo, allocator, patch_info_str, .{});
    for (patch_info.value.modules) |module| {
        try patch.add_module(module.module_type, module.module_name);
    }
    for (patch_info.value.cables) |cable| {
        try patch.add_cable(cable.src_module_name, cable.src_port_name, cable.dst_module_name, cable.dst_port_name);
    }
    patch_info.deinit();

    try patch.tick();

    patch.destroy(allocator);
}
