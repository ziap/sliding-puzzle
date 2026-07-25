const std = @import("std");

const Context = @import("Context.zig");
const StringMap = @import("string-map.zig").StringMap;

const generate = @import("generate.zig");
const evaluate = @import("evaluate.zig");

const Command = enum {
  generate,
  evaluate,
  help,
};

const commandMap = StringMap(Command).init(.{
  .generate = .generate,
  .evaluate = .evaluate,

  .@"--help" = .help,
  .@"-h" = .help,
});

const USAGE =
  \\Usage: sliding-puzzle <command> [options]
  \\
  \\Commands:
  \\  generate    Generate the pattern database
  \\  evaluate    Solve random puzzles and report the timings
  \\
  \\Options:
  \\  -h, --help  Display this help message
  \\
  \\Run `sliding-puzzle <command> --help` for the options of a command.
  \\
;

pub fn main(init: std.process.Init) !void {
  var out_buffer: [4096]u8 = undefined;
  var stdout: std.Io.File.Writer = .init(.stdout(), init.io, &out_buffer);
  const writer = &stdout.interface;

  var err_buffer: [4096]u8 = undefined;
  var stderr: std.Io.File.Writer = .init(.stderr(), init.io, &err_buffer);
  const err_writer = &stderr.interface;

  // The subcommand region is reset between generation and evaluation, which the
  // parsed arguments have to outlive, so they get a region of their own
  //
  // TODO: Replace both with one arena that supports checkpoints, so the
  // subcommand's working set can be rewound to a mark taken after parsing
  // instead of needing a second allocator to survive the reset
  var arg_arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
  defer arg_arena.deinit();

  var command_arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
  defer command_arena.deinit();

  const ctx: Context = .{
    .io = init.io,
    .arena = command_arena.allocator(),
    .writer = writer,
  };

  var iter = try init.minimal.args.iterateAllocator(arg_arena.allocator());
  defer iter.deinit();

  if (!iter.skip()) return error.NoProgramName;

  const name = iter.next() orelse {
    try err_writer.writeAll(USAGE);
    try err_writer.flush();
    return;
  };

  const command = commandMap.get(name) orelse {
    try err_writer.print("Error: Unknown command '{s}'\n\n", .{ name });
    try err_writer.writeAll(USAGE);
    try err_writer.flush();
    return;
  };

  switch (command) {
    .help => {
      try writer.writeAll(USAGE);
      try writer.flush();
    },
    .generate => {
      const args = generate.Args.parse(&iter, err_writer) catch return;
      generate.run(ctx, args) catch return;
    },
    .evaluate => {
      const args = evaluate.Args.parse(ctx.io, &iter, err_writer) catch return;
      if (args.iterations == 0) return;

      // Generate the database in place if it's missing, then drop the
      // generation buffers so evaluation starts from a clean region
      const cwd = std.Io.Dir.cwd();
      cwd.access(ctx.io, args.pdb, .{}) catch |err| switch (err) {
        error.FileNotFound => {
          generate.run(ctx, .{ .out = args.pdb }) catch return;
          _ = command_arena.reset(.free_all);
        },
        // Any other failure is reported when `evaluate` opens the file
        else => {},
      };

      evaluate.run(ctx, args) catch return;
    },
  }
}
