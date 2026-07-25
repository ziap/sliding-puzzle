const std = @import("std");

const core = @import("core");

const args = @import("args.zig");
const Context = @import("Context.zig");
const StringMap = @import("string-map.zig").StringMap;

const Board = core.Board;
const Pcg32 = core.Pcg32;
const Solver = core.HybridSolver;

const Heuristic = core.PatternDatabase;

const Param = enum {
  iterations,
  seed,
  pdb,
  help,
};

const paramMap = StringMap(Param).init(.{
  .@"--iter" = .iterations,
  .@"--seed" = .seed,
  .@"--pdb" = .pdb,
  .@"--help" = .help,

  .@"-i" = .iterations,
  .@"-s" = .seed,
  .@"-p" = .pdb,
  .@"-h" = .help,
});

pub const USAGE =
  \\Usage: main evaluate [options]
  \\
  \\Options:
  \\  -i, --iter <u32>  Number of puzzles to solve (default: 1000)
  \\  -s, --seed <u64>  Seed for the PRNG, decimal or 0x/0o/0b prefixed
  \\                    (default: random)
  \\  -p, --pdb <path>  Where to read the pattern database from, generated first
  \\                    if it doesn't exist (default: patterns.bin)
  \\  -h, --help        Display this help message
  \\
;

const BANNER_HEADER = "================== CONFIGURATION =================\n";
const BANNER_FOOTER = "==================================================\n\n";

pub const Args = struct {
  iterations: u32,
  seed: u64,
  pdb: []const u8,

  const DEFAULT_ITERATIONS = 1000;

  pub fn parse(
    io: std.Io,
    iter: *std.process.Args.Iterator,
    writer: *std.Io.Writer,
  ) !Args {
    var iterations: u32 = DEFAULT_ITERATIONS;
    var seed: ?u64 = null;
    var pdb: []const u8 = args.DEFAULT_PDB_PATH;

    while (iter.next()) |arg| {
      const param = paramMap.get(arg) orelse {
        try args.reportUnknownParameter(arg, writer);
        return error.UnknownParameter;
      };

      switch (param) {
        .iterations => iterations = try args.getU32(arg, iter, writer),
        .seed => seed = try args.getSeed(arg, iter, writer),
        .pdb => pdb = try args.getValue(arg, iter, writer),
        .help => {
          try writer.writeAll(USAGE);
          try writer.flush();
          return error.HelpIssued;
        },
      }
    }

    return .{
      .iterations = iterations,
      .seed = seed orelse randomSeed(io),
      .pdb = pdb,
    };
  }

  fn randomSeed(io: std.Io) u64 {
    var seed: u64 = undefined;
    std.Io.random(io, std.mem.asBytes(&seed));

    return seed;
  }

  // The seed is always a plain number so it can be pasted straight back into
  // `--seed` to reproduce a run
  pub fn display(self: Args, writer: *std.Io.Writer) !void {
    try writer.writeAll(BANNER_HEADER);
    try writer.print("Iterations : {d}\n", .{ self.iterations });
    try writer.print("Seed       : {d}\n", .{ self.seed });
    try writer.print("Database   : {s}\n", .{ self.pdb });
    try writer.writeAll(BANNER_FOOTER);
  }
};

fn load(ctx: Context, path: []const u8) !Heuristic {
  const database = try ctx.arena.create(Heuristic.Database);

  const cwd = std.Io.Dir.cwd();
  const pattern_file = cwd.openFile(ctx.io, path, .{}) catch |err| {
    std.debug.print("Error: Failed to open `{s}`: {}\n", .{ path, err });
    return err;
  };
  defer pattern_file.close(ctx.io);

  var buffer: [4096]u8 = undefined;
  var file_reader: std.Io.File.Reader = .init(pattern_file, ctx.io, &buffer);
  const reader = &file_reader.interface;

  reader.readSliceAll(database) catch |err| switch (err) {
    error.EndOfStream => {
      std.debug.print("Error: `{s}` is smaller than the expected {} bytes\n", .{
        path,
        Heuristic.TOTAL_SIZE * @sizeOf(Board.Cost),
      });
      return err;
    },
    else => {
      std.debug.print("Error: Failed to read `{s}`: {}\n", .{ path, err });
      return err;
    },
  };

  return .{ .database = database };
}

pub fn run(ctx: Context, self: Args) !void {
  const writer = ctx.writer;

  const heuristic = try load(ctx, self.pdb);

  // The solver is far too large for the stack, so give it static storage
  const solver = solver: {
    const S = struct {
      var solver: Solver = undefined;
    };

    break :solver &S.solver;
  };

  var rng: Pcg32 = .withSeed(self.seed);

  var max_time: f64 = 0;
  var total_time: f64 = 0;

  for (0..self.iterations) |_| {
    const board: Board = .randomUniform(&rng);
    try board.display(writer);
    try writer.flush();

    const start_time = std.Io.Timestamp.now(ctx.io, .awake);
    const solution = solver.solve(board, heuristic);
    const duration = start_time.untilNow(ctx.io, .awake);
    const elapsed = @as(f64, @floatFromInt(duration.toNanoseconds())) /
      std.time.ns_per_ms;

    max_time = @max(max_time, elapsed);
    total_time += elapsed;

    try writer.print("Solution length: {} - Time elapsed: {d}ms\n", .{
      solution.len,
      elapsed,
    });
    try writer.flush();
  }

  try self.display(writer);

  try writer.print("Longest time: {d}ms\n", .{ max_time });
  try writer.print("Average time: {d}ms\n", .{
    total_time / @as(f64, @floatFromInt(self.iterations)),
  });
  try writer.flush();
}
