const std = @import("std");

pub const Error = error{
    PortNotFound,
    DestinationPortHasCable,
};

pub const Port = struct {
    name: []const u8,
    value: f32,
    num_connected: u16,
};

pub fn create_port(allocator: std.mem.Allocator, name: []const u8) !*Port {
    const port = try allocator.create(Port);
    port.* = .{
        .name = name,
        .value = 0.0,
        .num_connected = 0,
    };
    return port;
}

pub fn destroy_port(port: *Port, allocator: std.mem.Allocator) void {
    allocator.destroy(port);
}

test "port" {
    const allocator = std.testing.allocator;
    const my_port = try create_port(allocator, "my_port");
    destroy_port(my_port, allocator);
}

fn Ports(comptime T: type) type {
    return [@typeInfo(T).Enum.fields.len]*Port;
}

pub fn create_ports(allocator: std.mem.Allocator, comptime T: type) !Ports(T) {
    const fields = @typeInfo(T).Enum.fields;
    var ports: [fields.len]*Port = undefined;
    inline for (0..fields.len) |i| {
        ports[i] = try create_port(allocator, fields[i].name);
    }
    return ports;
}

pub fn destroy_ports(ports: []*Port, allocator: std.mem.Allocator) void {
    for (ports) |port| {
        destroy_port(port, allocator);
    }
}

pub fn get_port_from_ports_by_name(ports: []*Port, name: []const u8) !*Port {
    for (ports) |port| {
        if (std.mem.eql(u8, port.name, name)) {
            return port;
        }
    }
    return Error.PortNotFound;
}

test "ports" {
    const allocator = std.testing.allocator;
    const MyPorts = enum { first_port, second_port };

    var my_ports = try create_ports(allocator, MyPorts);
    const my_port = try get_port_from_ports_by_name(&my_ports, "first_port");
    _ = my_port;

    destroy_ports(&my_ports, allocator);
}

pub const Cable = struct {
    src_port: *Port,
    dst_port: *Port,
    src_module_name: *[]const u8,
    dst_module_name: *[]const u8,
};

pub fn create_cable(
    allocator: std.mem.Allocator,
    src_port: *Port,
    dst_port: *Port,
    src_module_name: *[]const u8,
    dst_module_name: *[]const u8,
) !*Cable {
    if (dst_port.num_connected > 0) {
        return Error.DestinationPortHasCable;
    }
    const self = try allocator.create(Cable);
    self.* = .{
        .src_port = src_port,
        .dst_port = dst_port,
        .src_module_name = src_module_name,
        .dst_module_name = dst_module_name,
    };
    src_port.num_connected += 1;
    dst_port.num_connected += 1;
    return self;
}

pub fn destroy_cable(cable: *Cable, allocator: std.mem.Allocator) void {
    cable.src_port.value = 0.0;
    cable.dst_port.value = 0.0;
    cable.src_port.num_connected -= 1;
    cable.dst_port.num_connected -= 1;
    allocator.destroy(cable);
}

test "cable" {
    const allocator = std.testing.allocator;
    const src_port = try create_port(allocator, "src_port");
    const dst_port = try create_port(allocator, "dst_port");

    var module_name: []const u8 = "test";
    const my_cable = try create_cable(allocator, src_port, dst_port, &module_name, &module_name);

    destroy_cable(my_cable, allocator);
    destroy_port(src_port, allocator);
    destroy_port(dst_port, allocator);
}

pub fn destroy_all_cables(cables: *std.AutoHashMap(*Cable, void), allocator: std.mem.Allocator) void {
    var cable_iterator = cables.iterator();
    while (cable_iterator.next()) |entry| {
        destroy_cable(entry.key_ptr.*, allocator);
    }
    cables.deinit();
}

pub fn step_all_cables(cables: *std.AutoHashMap(*Cable, void)) void {
    var cable_iterator = cables.iterator();
    while (cable_iterator.next()) |cable| {
        cable.key_ptr.*.dst_port.value = cable.key_ptr.*.src_port.value;
    }
}

pub const CableInfo = struct {
    src_module_name: []const u8,
    src_port_name: []const u8,
    dst_module_name: []const u8,
    dst_port_name: []const u8,
};

pub fn create_cables_info(cables: *std.AutoHashMap(*Cable, void), allocator: std.mem.Allocator) ![]const CableInfo {
    const cables_info = try allocator.alloc(CableInfo, cables.count());

    var i: u32 = 0;
    var cable_iterator = cables.iterator();
    while (cable_iterator.next()) |cable| : (i += 1) {
        cables_info[i] = .{ .src_port_name = cable.key_ptr.*.src_port.name, .dst_port_name = cable.key_ptr.*.dst_port.name, .src_module_name = cable.key_ptr.*.src_module_name.*, .dst_module_name = cable.key_ptr.*.dst_module_name.* };
    }
    return cables_info;
}

test "cables" {
    const allocator = std.testing.allocator;
    const src_port = try create_port(allocator, "src_port");
    const dst_port = try create_port(allocator, "dst_port");
    var module_name: []const u8 = "test";

    var my_cables = std.AutoHashMap(*Cable, void).init(allocator);
    const my_cable = try create_cable(allocator, src_port, dst_port, &module_name, &module_name);

    try my_cables.put(my_cable, {});

    step_all_cables(&my_cables);

    const my_cables_info = try create_cables_info(&my_cables, allocator);
    defer allocator.free(my_cables_info);

    destroy_all_cables(&my_cables, allocator);
    destroy_port(src_port, allocator);
    destroy_port(dst_port, allocator);
}
