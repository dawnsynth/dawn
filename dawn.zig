const std = @import("std");
const cli = @import("cli");
const dawn = @import("dawn");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var port_receive_option = cli.Option{
    .long_name = "port_receive",
    .help = "port to receive osc messages on (optional).",
    .value = cli.OptionValue{ .int = 2502 },
};

var port_send_option = cli.Option{
    .long_name = "port_send",
    .help = "port to send osc messages to (optional).",
    .value = cli.OptionValue{ .int = 2501 },
};

var app = &cli.App{
    .name = "dawn",
    .version = dawn.version,
    .description =
    \\dawn is a modular synth.
    ,
    .options = &.{ &port_send_option, &port_receive_option },
    .action = run_dawn,
    .help_config = cli.HelpConfig{
        .color_usage = cli.ColorUsage.never,
    },
};

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const stdout = std.io.getStdOut().writer();
    const prefix = "[" ++ comptime level.asText() ++ "] " ++ "(" ++ @tagName(scope) ++ ") ";
    nosuspend stdout.print(prefix ++ format ++ "\n", args) catch return;
}

pub const std_options = struct {
    pub const log_level = .info;
    pub const logFn = log;
};

var patch: *dawn.Patch = undefined;

fn run_dawn(_: []const []const u8) !void {
    var port_send = port_send_option.value.int orelse unreachable;
    var port_receive = port_receive_option.value.int orelse unreachable;

    const logger = std.log.scoped(.dawn);
    logger.info("start of session", .{});
    defer logger.info("end of session", .{});

    patch = try dawn.Patch.create(allocator);
    patch.port_receive = @intCast(port_receive);
    patch.port_send = @intCast(port_send);
    logger.info("initialized patch", .{});
    defer patch.destroy(allocator);

    logger.info("adding opensoundcontrol module to patch", .{});
    try patch.add_module("opensoundcontrol", "opensoundcontrol");

    logger.info("adding soundio module to patch", .{});
    try patch.add_module("soundio", "soundio");

    while (true) {
        std.time.sleep(std.time.ns_per_s); // TODO: reconsider
    }
}

pub fn main() !void {
    return cli.run(app, allocator);
}
