const std = @import("std");

const args = @import("args.zig");
const Context = @import("Context.zig");
const StringMap = @import("string-map.zig").StringMap;

const Heuristic = @import("pattern-database.zig").Default;

const Param = enum {
  out,
  help,
};

const paramMap = StringMap(Param).init(.{
  .@"--out" = .out,
  .@"--help" = .help,

  .@"-o" = .out,
  .@"-h" = .help,
});

pub const USAGE =
  \\Usage: main generate [options]
  \\
  \\Options:
  \\  -o, --out <path>  Pattern database output path (default: patterns.bin)
  \\  -h, --help        Display this help message
  \\
;

pub const Args = struct {
  out: []const u8,

  pub fn parse(iter: *std.process.Args.Iterator, writer: *std.Io.Writer) !Args {
    var out: []const u8 = args.DEFAULT_PDB_PATH;

    while (iter.next()) |arg| {
      const param = paramMap.get(arg) orelse {
        try args.reportUnknownParameter(arg, writer);
        return error.UnknownParameter;
      };

      switch (param) {
        .out => out = try args.getValue(arg, iter, writer),
        .help => {
          try writer.writeAll(USAGE);
          try writer.flush();
          return error.HelpIssued;
        },
      }
    }

    return .{ .out = out };
  }
};

pub fn run(ctx: Context, self: Args) !void {
  const writer = ctx.writer;

  // Claim the output file before generating, so an unusable path fails now
  // rather than after several seconds of work
  const cwd = std.Io.Dir.cwd();
  const out_file = cwd.createFile(ctx.io, self.out, .{}) catch |err| {
    std.debug.print("Error: Failed to create `{s}`: {}\n", .{ self.out, err });
    return err;
  };
  defer out_file.close(ctx.io);

  const database = try ctx.arena.create(Heuristic.Database);
  const buffer = try ctx.arena.create(Heuristic.ScratchBuffer);

  const heuristic: Heuristic = .{ .database = database };

  try writer.writeAll("Generating the pattern database\n");
  try writer.flush();

  const start_time = std.Io.Timestamp.now(ctx.io, .awake);
  heuristic.generate(buffer);

  const duration = start_time.untilNow(ctx.io, .awake);
  const elapsed = @as(f64, @floatFromInt(duration.toNanoseconds())) /
    std.time.ns_per_ms;
  try writer.print("Generated the pattern database in: {d}ms\n", .{ elapsed });

  try writer.print("Exporting the pattern database to `{s}`\n", .{ self.out });
  try writer.flush();

  out_file.writePositionalAll(ctx.io, database, 0) catch |err| {
    std.debug.print("Error: Failed to write `{s}`: {}\n", .{ self.out, err });
    return err;
  };
}
