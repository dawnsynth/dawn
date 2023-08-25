const std = @import("std");
const dawn = @import("../main.zig");
const network = @import("network");
const tinyosc = @import("tinyosc");

const Endpoint = enum { add_module, remove_module, add_cable, remove_cable, set_param, get_version, get_patch, set_patch, unknown };

fn endpoint_from_string(str: []const u8) Endpoint {
    inline for (@typeInfo(Endpoint).Enum.fields) |field| {
        if (std.mem.eql(u8, field.name, str)) {
            return @enumFromInt(field.value);
        }
    }
    return Endpoint.unknown;
}

pub const Module = struct {
    pub const Self = @This();

    patch: *dawn.Patch,

    socket: network.Socket,
    socketset: network.SocketSet,
    osc_msg: *tinyosc.c.tosc_message,
    polling_frequency: u16,

    pub fn create(allocator: std.mem.Allocator, patch: *dawn.Patch) !*Self {
        // TODO: check whether an opensoundcontrol module is already in patch, allow only one
        try network.init();

        var socket = try network.Socket.create(.ipv4, .udp);
        try socket.bind(.{
            .address = .{ .ipv4 = network.Address.IPv4.any },
            .port = patch.port_receive,
        });
        std.log.info("listening for osc messages at {}", .{try socket.getLocalEndPoint()});
        try socket.setBroadcast(true);

        var event = network.SocketEvent{ .read = true, .write = false };
        var socketset = try network.SocketSet.init(allocator);
        try socketset.add(socket, event);

        var osc_msg = try allocator.create(tinyosc.c.tosc_message);

        const self = try allocator.create(Self);
        self.* = .{
            .patch = patch,
            .socket = socket,
            .socketset = socketset,
            .osc_msg = osc_msg,
            .polling_frequency = 1000, // TODO: reconsider frequency
        };
        return self;
    }

    pub fn destroy_hook(self: *Self, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.socketset.deinit();
        self.socket.close();
    }

    pub fn tick(self: *Self) !void {
        if (self.patch.num_steps % self.polling_frequency != 0) return;

        const wait_msg = network.waitForSocketEvent(&self.socketset, 0) catch 0;
        if (wait_msg == 0) return;

        var buffer: [1024]u8 = undefined; // TODO: reconsider size of buffer
        const recv_msg = self.socket.receive(&buffer) catch unreachable;
        _ = tinyosc.c.tosc_parseMessage(self.osc_msg, &buffer, @intCast(recv_msg));

        var address = tinyosc.c.tosc_getAddress(self.osc_msg);
        //std.log.info("msg on address: {s}", .{address});
        var parts = std.mem.split(u8, std.mem.sliceTo(address, 0), "/");

        _ = parts.next() orelse return; // TODO: log error? applies to cases below as well
        var endpoint = parts.next() orelse return;

        switch (endpoint_from_string(endpoint)) {
            Endpoint.add_module => {
                // /add_module ss <module_type> <module_name>
                const module_type = tinyosc.getNextString(self.osc_msg);
                const module_name = tinyosc.getNextString(self.osc_msg);
                std.log.info("/add_module ss {s} {s}", .{ module_type, module_name });
                // TODO: make sure allocation below gets cleaned up on module removal
                var module_name_copy = try self.patch.allocator.dupe(u8, module_name);
                try self.patch.add_module(module_type, module_name_copy);
            },
            Endpoint.remove_module => {
                // /remove_module s <module_name>
                const module_name = tinyosc.getNextString(self.osc_msg);
                std.log.info("/remove_module s {s}", .{module_name});
                try self.patch.remove_module(module_name);
            },
            Endpoint.add_cable => {
                // /add_cable ssss <src_module_name> <src_port_name> <dst_module_name> <dst_port_name>
                const src_module_name = tinyosc.getNextString(self.osc_msg);
                const src_port_name = tinyosc.getNextString(self.osc_msg);
                const dst_module_name = tinyosc.getNextString(self.osc_msg);
                const dst_port_name = tinyosc.getNextString(self.osc_msg);
                std.log.info("/add_cable ssss {s} {s} {s} {s}", .{ src_module_name, src_port_name, dst_module_name, dst_port_name });
                try self.patch.add_cable(src_module_name, src_port_name, dst_module_name, dst_port_name);
            },
            Endpoint.remove_cable => {
                // /remove_cable ssss <src_module_name> <src_port_name> <dst_module_name> <dst_port_name>
                const src_module_name = tinyosc.getNextString(self.osc_msg);
                const src_port_name = tinyosc.getNextString(self.osc_msg);
                const dst_module_name = tinyosc.getNextString(self.osc_msg);
                const dst_port_name = tinyosc.getNextString(self.osc_msg);
                std.log.info("/remove_cable ssss {s} {s} {s} {s}", .{ src_module_name, src_port_name, dst_module_name, dst_port_name });
                try self.patch.remove_cable_by_names(src_module_name, src_port_name, dst_module_name, dst_port_name);
            },
            Endpoint.set_param => {
                // /set_param ssf <module_name> <param_name> <value>
                // TODO: consider whether to keep as is or if <module_name>/<param_name> should be part of address
                const module_name = tinyosc.getNextString(self.osc_msg);
                const param_name = tinyosc.getNextString(self.osc_msg);
                const value: f32 = tinyosc.c.tosc_getNextFloat(self.osc_msg);
                std.log.info("/set_param ssd {s} {s} {d:.5}", .{ module_name, param_name, value });
                const module = self.patch.modules.get(module_name) orelse return;
                try module.setParam(param_name, value);
            },
            Endpoint.get_version => {
                // /get_version
                std.log.info("/get_version", .{});
                const destAddress = network.EndPoint{ .address = network.Address{ .ipv4 = network.Address.IPv4.broadcast }, .port = self.patch.port_send };
                var reply_buffer: [1024]u8 = undefined; // TODO: buffer length?
                var len = tinyosc.c.tosc_writeMessage(&buffer, @sizeOf(@TypeOf(reply_buffer)), "/get_version", "s", dawn.version);
                const N = self.socket.sendTo(destAddress, buffer[0..len]) catch unreachable;
                std.log.info("sent {any} bytes", .{N});
            },
            Endpoint.get_patch => {
                // /get_patch
                std.log.info("/get_patch", .{});
                const patch_info_str = try dawn.create_patch_info_string(self.patch, self.patch.allocator);
                defer self.patch.allocator.free(patch_info_str);
                std.log.info("{s}", .{patch_info_str});
                // TODO: cast patch_info_str so that it is suitable to be send as reply
                std.log.info("not implemented.", .{});
            },
            Endpoint.set_patch => {
                // /set_patch s (or b?)
                std.log.info("/set_patch", .{});
                // TODO: deserialize patch using std.json.parseFromSlice
                std.log.info("not implemented.", .{});
            },
            else => {
                std.log.info("unknown endpoint.", .{});
                return;
            },
        }
    }
};
