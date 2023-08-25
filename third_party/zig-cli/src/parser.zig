const std = @import("std");
const Allocator = std.mem.Allocator;

const command = @import("command.zig");
const help = @import("./help.zig");
const argp = @import("./arg.zig");
const Printer = @import("./Printer.zig");

pub const ParseResult = struct {
    action: command.Action,
    args: []const []const u8,
};

pub fn run(app: *const command.App, alloc: Allocator) anyerror!void {
    var iter = try std.process.argsWithAllocator(alloc);
    defer iter.deinit();

    var cr = try Parser(std.process.ArgIterator).init(app, iter, alloc);
    defer cr.deinit();

    var result = try cr.parse();
    return result.action(result.args);
}

var help_option = command.Option{
    .long_name = "help",
    .help = "Show this help output.",
    .short_alias = 'h',
    .value = command.OptionValue{ .bool = false },
};

const ValueList = std.ArrayList([]const u8);
const ValueListMap = std.AutoHashMap(*command.Option, ValueList);

pub fn Parser(comptime Iterator: type) type {
    return struct {
        const Self = @This();

        alloc: Allocator,
        arg_iterator: Iterator,
        app: *const command.App,
        command_path: std.ArrayList(*const command.Command),
        captured_arguments: std.ArrayList([]const u8),
        value_lists: ?ValueListMap,

        pub fn init(app: *const command.App, it: Iterator, alloc: Allocator) !Self {
            return Self{
                .alloc = alloc,
                .arg_iterator = it,
                .app = app,
                .command_path = try std.ArrayList(*const command.Command).initCapacity(alloc, 16),
                .captured_arguments = try std.ArrayList([]const u8).initCapacity(alloc, 16),
                .value_lists = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.captured_arguments.deinit();
            self.command_path.deinit();
        }

        inline fn current_command(self: *const Self) *const command.Command {
            return self.command_path.items[self.command_path.items.len - 1];
        }

        pub fn parse(self: *Self) anyerror!ParseResult {
            const app_command = command.Command{
                .name = self.app.name,
                .description = self.app.description,
                .help = "",
                .action = self.app.action,
                .subcommands = self.app.subcommands,
                .options = self.app.options,
            };
            try self.command_path.append(&app_command);

            self.validate_command(&app_command);
            _ = self.next_arg();
            var args_only = false;
            while (self.next_arg()) |arg| {
                if (args_only) {
                    try self.captured_arguments.append(arg);
                } else if (argp.interpret(arg)) |int| {
                    args_only = try self.process_interpretation(&int);
                } else |err| {
                    switch (err) {
                        error.MissingOptionArgument => self.fail("missing argument: '{s}'", .{arg}),
                    }
                }
            }
            return self.finalize();
        }

        fn finalize(self: *Self) !ParseResult {
            self.ensure_all_required_set(self.current_command());
            var args = try self.captured_arguments.toOwnedSlice();

            if (self.value_lists) |vl| {
                var it = vl.iterator();
                while (it.next()) |entry| {
                    var option: *command.Option = entry.key_ptr.*;
                    option.value.string_list = try entry.value_ptr.toOwnedSlice();
                }
                self.value_lists.?.deinit();
            }

            if (self.current_command().action) |action| {
                return ParseResult{ .action = action, .args = args };
            } else {
                self.fail("command '{s}': no subcommand provided", .{self.current_command().name});
                unreachable;
            }
        }

        fn process_interpretation(self: *Self, int: *const argp.ArgumentInterpretation) !bool {
            var args_only = false;
            try switch (int.*) {
                .option => |opt| self.process_option(&opt),
                .double_dash => {
                    args_only = true;
                },
                .other => |some_name| {
                    if (find_subcommand(self.current_command(), some_name)) |cmd| {
                        self.ensure_all_required_set(self.current_command());
                        self.validate_command(cmd);
                        try self.command_path.append(cmd);
                    } else {
                        try self.captured_arguments.append(some_name);
                    }
                },
            };
            return args_only;
        }

        fn next_arg(self: *Self) ?[]const u8 {
            return self.arg_iterator.next();
        }

        fn process_option(self: *Self, option: *const argp.OptionInterpretation) !void {
            var opt: *command.Option = switch (option.option_type) {
                .long => self.find_option_by_name(self.current_command(), option.name),
                .short => a: {
                    self.set_boolean_options(self.current_command(), option.name[0 .. option.name.len - 1]);
                    break :a self.find_option_by_alias(self.current_command(), option.name[option.name.len - 1]);
                },
            };

            if (opt == &help_option) {
                try help.print_command_help(self.app, try self.command_path.toOwnedSlice());
                std.os.exit(0);
            }

            switch (opt.value) {
                .bool => opt.value = command.OptionValue{ .bool = true },
                else => {
                    const arg = option.value orelse self.next_arg() orelse {
                        self.fail("missing argument for {s}", .{opt.long_name});
                        unreachable;
                    };
                    try self.parse_and_set_option_value(arg, opt);
                },
            }
        }

        fn parse_and_set_option_value(self: *Self, text: []const u8, option: *command.Option) !void {
            switch (option.value) {
                .bool => unreachable,
                .string => option.value = command.OptionValue{ .string = text },
                .int => {
                    if (std.fmt.parseInt(i64, text, 10)) |iv| {
                        option.value = command.OptionValue{ .int = iv };
                    } else |_| {
                        self.fail("option({s}): cannot parse int value", .{option.long_name});
                        unreachable;
                    }
                },
                .float => {
                    if (std.fmt.parseFloat(f64, text)) |fv| {
                        option.value = command.OptionValue{ .float = fv };
                    } else |_| {
                        self.fail("option({s}): cannot parse float value", .{option.long_name});
                        unreachable;
                    }
                },
                .string_list => {
                    if (self.value_lists == null) {
                        self.value_lists = ValueListMap.init(self.alloc);
                    }

                    var res = try self.value_lists.?.getOrPut(option);
                    if (!res.found_existing) {
                        res.value_ptr.* = try ValueList.initCapacity(self.alloc, 16);
                    }
                    try res.value_ptr.append(text);
                },
            }
        }

        fn fail(self: *const Self, comptime fmt: []const u8, args: anytype) void {
            var p = Printer.init(std.io.getStdErr(), self.app.help_config.color_usage);

            p.printInColor(self.app.help_config.color_error, "ERROR");
            p.format(": ", .{});
            p.format(fmt, args);
            p.write(&.{'\n'});
            std.os.exit(1);
        }

        fn find_option_by_name(self: *const Self, cmd: *const command.Command, option_name: []const u8) *command.Option {
            if (std.mem.eql(u8, "help", option_name)) {
                return &help_option;
            }
            if (cmd.options) |option_list| {
                for (option_list) |option| {
                    if (std.mem.eql(u8, option.long_name, option_name)) {
                        return option;
                    }
                }
            }
            self.fail("no such option '--{s}'", .{option_name});
            unreachable;
        }

        fn find_option_by_alias(self: *const Self, cmd: *const command.Command, option_alias: u8) *command.Option {
            if (option_alias == 'h') {
                return &help_option;
            }
            if (cmd.options) |option_list| {
                for (option_list) |option| {
                    if (option.short_alias) |alias| {
                        if (alias == option_alias) {
                            return option;
                        }
                    }
                }
            }
            self.fail("no such option alias '-{c}'", .{option_alias});
            unreachable;
        }

        fn validate_command(self: *const Self, cmd: *const command.Command) void {
            if (cmd.subcommands == null) {
                if (cmd.action == null) {
                    self.fail("command '{s}' has neither subcommands no an aciton assigned", .{cmd.name});
                }
            } else {
                if (cmd.action != null) {
                    self.fail("command '{s}' has subcommands and an action assigned. Commands with subcommands are not allowed to have action.", .{cmd.name});
                }
            }
        }

        fn set_boolean_options(self: *const Self, cmd: *const command.Command, options: []const u8) void {
            for (options) |alias| {
                var opt = self.find_option_by_alias(cmd, alias);
                if (opt.value == command.OptionValue.bool) {
                    opt.value.bool = true;
                } else {
                    self.fail("'-{c}' is not a boolean option", .{alias});
                }
            }
        }

        fn ensure_all_required_set(self: *const Self, cmd: *const command.Command) void {
            if (cmd.options) |list| {
                for (list) |option| {
                    if (option.required) {
                        var not_set = switch (option.value) {
                            .bool => false,
                            .string => |x| x == null,
                            .int => |x| x == null,
                            .float => |x| x == null,
                            .string_list => |x| x == null,
                        };
                        if (not_set) {
                            self.fail("missing required option '{s}'", .{option.long_name});
                        }
                    }
                }
            }
        }
    };
}

fn find_subcommand(cmd: *const command.Command, subcommand_name: []const u8) ?*const command.Command {
    if (cmd.subcommands) |sc_list| {
        for (sc_list) |sc| {
            if (std.mem.eql(u8, sc.name, subcommand_name)) {
                return sc;
            }
        }
    }
    return null;
}
