const std = @import("std");
const cli = @import("cli");
const dawn = @import("dawn");

const network = @import("network");

pub const c = @cImport({
    @cInclude("tinyosc.h");
});

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var port_send_option = cli.Option{
    .long_name = "port_send",
    .help = "port to send osc messages to (optional). defaults to 2502.",
    .value = cli.OptionValue{ .int = 2502 },
};

var port_receive_option = cli.Option{
    .long_name = "port_receive",
    .help = "port to receive osc messages on (optional). defaults to 2501.",
    .value = cli.OptionValue{ .int = 2501 },
};

var buffer: [1024]u8 = undefined; // TODO: reconsider size of buffer

pub fn sendBuffer(wait: bool) !void {
    try network.init();
    defer network.deinit();

    var socket = try network.Socket.create(.ipv4, .udp);
    defer socket.close();

    var port_receive = port_receive_option.value.int orelse unreachable;
    var port_send = port_send_option.value.int orelse unreachable;

    try socket.setBroadcast(true);
    try socket.bind(.{
        .address = .{ .ipv4 = network.Address.IPv4.any },
        .port = @intCast(port_receive),
    });
    const destAddress = network.EndPoint{ .address = network.Address{ .ipv4 = network.Address.IPv4.broadcast }, .port = @intCast(port_send) };

    const N = try socket.sendTo(destAddress, &buffer);
    std.debug.print("sent {any} bytes.\n", .{N});

    if (wait) {
        const r = socket.reader();
        std.debug.print("waiting for messages on socket {!}\n", .{socket.getLocalEndPoint()});
        while (true) {
            const bytes = try r.read(buffer[0..]);
            std.debug.print("received {s}.\n", .{buffer[0..bytes]});
            //std.time.sleep(std.time.ns_per_s);
            return;
        }
    }
}

var add_module_type_option = cli.Option{
    .long_name = "module_type",
    .help = "type of module (required). for now, see `modules/` folder for types available.",
    .required = true,
    .value = cli.OptionValue{ .string = null },
};

var add_module_name_option = cli.Option{
    .long_name = "module_name",
    .help = "name of module (required). used as a reference. should not contain any /.",
    .required = true,
    .value = cli.OptionValue{ .string = null },
};

fn run_add_module(_: []const []const u8) !void {
    var module_type = add_module_type_option.value.string orelse unreachable;
    var module_name = add_module_name_option.value.string orelse unreachable;
    _ = c.tosc_writeMessage(&buffer, @sizeOf(@TypeOf(buffer)), "/add_module", "ss", module_type.ptr, module_name.ptr);
    try sendBuffer(false);
}

const add_module_cmd = cli.Command{
    .name = "add_module",
    .help = "adds module to patch",
    .description =
    \\requires module type and name.
    ,
    .options = &.{
        &add_module_type_option,
        &add_module_name_option,
        &port_send_option,
    },
    .action = run_add_module,
};

var remove_module_name_option = cli.Option{
    .long_name = "module_name",
    .help = "name of module (required). used as a reference. should not contain any /.",
    .required = true,
    .value = cli.OptionValue{ .string = null },
};

fn run_remove_module(_: []const []const u8) !void {
    var module_name = remove_module_name_option.value.string orelse unreachable;
    _ = c.tosc_writeMessage(&buffer, @sizeOf(@TypeOf(buffer)), "/remove_module", "s", module_name.ptr);
    try sendBuffer(false);
}

const remove_module_cmd = cli.Command{
    .name = "remove_module",
    .help = "removes module from patch",
    .description =
    \\requires module name.
    ,
    .options = &.{
        &remove_module_name_option,
        &port_send_option,
    },
    .action = run_remove_module,
};

var add_cable_src_module_name_option = cli.Option{
    .long_name = "src_module_name",
    .help = "name of source module (required).",
    .required = true,
    .value = cli.OptionValue{ .string = null },
};

var add_cable_src_port_name_option = cli.Option{
    .long_name = "src_port_name",
    .help = "name of output port on source module (required). for now, see module code for available ports.",
    .required = true,
    .value = cli.OptionValue{ .string = null },
};

var add_cable_dst_module_name_option = cli.Option{
    .long_name = "dst_module_name",
    .help = "name of destination module (required).",
    .required = true,
    .value = cli.OptionValue{ .string = null },
};

var add_cable_dst_port_name_option = cli.Option{
    .long_name = "dst_port_name",
    .help = "name of input port on destination module (required). for now, see module code for available ports.",
    .required = true,
    .value = cli.OptionValue{ .string = null },
};

fn run_add_cable(_: []const []const u8) !void {
    var src_module_name = add_cable_src_module_name_option.value.string orelse unreachable;
    var src_port_name = add_cable_src_port_name_option.value.string orelse unreachable;
    var dst_module_name = add_cable_dst_module_name_option.value.string orelse unreachable;
    var dst_port_name = add_cable_dst_port_name_option.value.string orelse unreachable;
    _ = c.tosc_writeMessage(&buffer, @sizeOf(@TypeOf(buffer)), "/add_cable", "ssss", src_module_name.ptr, src_port_name.ptr, dst_module_name.ptr, dst_port_name.ptr);
    try sendBuffer(false);
}

const add_cable_cmd = cli.Command{
    .name = "add_cable",
    .help = "adds cable to patch",
    .description =
    \\requires names of source module, source port, destination module, destination port. 
    ,
    .options = &.{
        &add_cable_src_module_name_option,
        &add_cable_src_port_name_option,
        &add_cable_dst_module_name_option,
        &add_cable_dst_port_name_option,
        &port_send_option,
    },
    .action = run_add_cable,
};

var remove_cable_src_module_name_option = cli.Option{
    .long_name = "src_module_name",
    .help = "name of source module (required).",
    .required = true,
    .value = cli.OptionValue{ .string = null },
};

var remove_cable_src_port_name_option = cli.Option{
    .long_name = "src_port_name",
    .help = "name of output port on source module (required). for now, see module code for available ports.",
    .required = true,
    .value = cli.OptionValue{ .string = null },
};

var remove_cable_dst_module_name_option = cli.Option{
    .long_name = "dst_module_name",
    .help = "name of destination module (required).",
    .required = true,
    .value = cli.OptionValue{ .string = null },
};

var remove_cable_dst_port_name_option = cli.Option{
    .long_name = "dst_port_name",
    .help = "name of input port on destination module (required). for now, see module code for available ports.",
    .required = true,
    .value = cli.OptionValue{ .string = null },
};

fn run_remove_cable(_: []const []const u8) !void {
    var src_module_name = remove_cable_src_module_name_option.value.string orelse unreachable;
    var src_port_name = remove_cable_src_port_name_option.value.string orelse unreachable;
    var dst_module_name = remove_cable_dst_module_name_option.value.string orelse unreachable;
    var dst_port_name = remove_cable_dst_port_name_option.value.string orelse unreachable;
    _ = c.tosc_writeMessage(&buffer, @sizeOf(@TypeOf(buffer)), "/remove_cable", "ssss", src_module_name.ptr, src_port_name.ptr, dst_module_name.ptr, dst_port_name.ptr);
    try sendBuffer(false);
}

const remove_cable_cmd = cli.Command{
    .name = "remove_cable",
    .help = "removes cable from patch",
    .description =
    \\requires names of source module, source port, destination module, destination port. 
    ,
    .options = &.{
        &remove_cable_src_module_name_option,
        &remove_cable_src_port_name_option,
        &remove_cable_dst_module_name_option,
        &remove_cable_dst_port_name_option,
        &port_send_option,
    },
    .action = run_remove_cable,
};

var set_param_module_name_option = cli.Option{
    .long_name = "module_name",
    .help = "name of module (required).",
    .required = true,
    .value = cli.OptionValue{ .string = null },
};

var set_param_param_name_option = cli.Option{
    .long_name = "param_name",
    .help = "name of param (required).",
    .required = true,
    .value = cli.OptionValue{ .string = null },
};

var set_param_value_option = cli.Option{
    .long_name = "value",
    .help = "new value for parameter.",
    .required = true,
    .value = cli.OptionValue{ .float = null },
};

fn run_set_param(_: []const []const u8) !void {
    var module_name = set_param_module_name_option.value.string orelse unreachable;
    var param_name = set_param_param_name_option.value.string orelse unreachable;
    var value: f32 = @floatCast(set_param_value_option.value.float orelse unreachable);
    _ = c.tosc_writeMessage(&buffer, @sizeOf(@TypeOf(buffer)), "/set_param", "ssf", module_name.ptr, param_name.ptr, value);
    try sendBuffer(false);
}

const set_param_cmd = cli.Command{
    .name = "set_param",
    .help = "sets param to new value.",
    .description =
    \\requires module name, param name, and value.
    ,
    .options = &.{
        &set_param_module_name_option,
        &set_param_param_name_option,
        &set_param_value_option,
        &port_send_option,
    },
    .action = run_set_param,
};

fn run_get_patch(_: []const []const u8) !void {
    _ = c.tosc_writeMessage(&buffer, @sizeOf(@TypeOf(buffer)), "/get_patch", "s", "empty");
    try sendBuffer(false);
    std.debug.print("see dawn's stdout for patch info.\n", .{});
    std.debug.print("not waiting for reply as this is not implemented yet.\n", .{});
}

const get_patch_cmd = cli.Command{
    .name = "get_patch",
    .help = "gets current patch",
    .description =
    \\partially implemented.
    ,
    .options = &.{
        &port_send_option,
        &port_receive_option,
    },
    .action = run_get_patch,
};

fn run_get_version(_: []const []const u8) !void {
    _ = c.tosc_writeMessage(&buffer, @sizeOf(@TypeOf(buffer)), "/get_version", "s", "empty");
    try sendBuffer(true);
}

const get_version_cmd = cli.Command{
    .name = "get_version",
    .help = "queries dawn for its version",
    .description =
    \\receives version reply back. demonstrates bi-directional messaging.
    ,
    .options = &.{
        &port_send_option,
        &port_receive_option,
    },
    .action = run_get_version,
};

var app = &cli.App{
    .name = "dusk",
    .version = dawn.version, // Keep versions in sync
    .description =
    \\dusk is a simple osc client for dawn.
    \\invoke with a command from the list below.
    \\to learn more about a command, add --help to it for more info.
    ,
    .subcommands = &.{
        &add_module_cmd,
        &remove_module_cmd,
        &add_cable_cmd,
        &remove_cable_cmd,
        &set_param_cmd,
        &get_patch_cmd,
        &get_version_cmd,
    },
    .help_config = cli.HelpConfig{
        .color_usage = cli.ColorUsage.never,
    },
};

pub fn main() !void {
    return cli.run(app, allocator);
}
