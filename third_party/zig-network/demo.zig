const std = @import("std");
const network = @import("network");

pub fn main() !void {
    try network.init();
    defer network.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var socket = try network.Socket.create(.ipv4, .udp);
    defer socket.close();
    try socket.bind(.{
        .address = .{ .ipv4 = network.Address.IPv4.any },
        .port = 2501,
    });

    var socketset = try network.SocketSet.init(allocator);
    defer socketset.deinit();
    var event = network.SocketEvent{ .read = true, .write = false };
    try socketset.add(socket, event);

    const wait_msg = network.waitForSocketEvent(&socketset, 0) catch 0;
    _ = wait_msg;

    // ...
}
