const std = @import("std");

const Pcg32 = @import("Pcg32.zig");
const Board = @import("Board.zig");

const Solver = @import("solver.zig").HybridSolver;

const Cost = Board.Cost;

const Heuristic = @import("pattern-database.zig").Default;

// TODO: Parse the command-line arguments
// - seed for RNG
// - number of games
// - path to pattern database
// - ...
pub fn main(init: std.process.Init) !void {
  const allocator = init.arena.allocator();

  var buffer: [4096]u8 = undefined;
  var stdout: std.Io.File.Writer = .init(.stdout(), init.io, &buffer);
  const writer = &stdout.interface;

  const solver = blk: {
    const S = struct {
      var solver: Solver = undefined;
    };

    break :blk &S.solver;
  };
  
  var rng: Pcg32 = .withSeed(1337);

  const heuristic: Heuristic = blk: {
    const database = try allocator.create(Heuristic.Database);

    const FILE_PATH = "patterns.bin";
    const pattern_file = std.Io.Dir.cwd().openFile(init.io, FILE_PATH, .{}) catch |err| {
      std.debug.print("Error: Failed to open `{s}`: {}\n", .{ FILE_PATH, err });
      return;
    };
    defer pattern_file.close(init.io);

    var pattern_buffer: [4096]u8 = undefined;
    var pattern_reader: std.Io.File.Reader = .init(pattern_file, init.io, &pattern_buffer);
    const reader = &pattern_reader.interface;

    reader.readSliceAll(database) catch |err| switch (err) {
      error.EndOfStream => {
        std.debug.print("Error: `{s}` is smaller than the expected {} bytes\n", .{
          FILE_PATH,
          Heuristic.TOTAL_SIZE * @sizeOf(Board.Cost),
        });
        return;
      },
      else => {
        std.debug.print("Error: Failed to read `{s}`: {}\n", .{ FILE_PATH, err });
        return;
      },
    };

    break :blk .{ .database = database };
  };

  var max_time: f64 = 0;
  var total_time: f64 = 0;

  const TOTAL_GAMES = 1000;

  for (0..TOTAL_GAMES) |_| {
    const board: Board = .randomUniform(&rng);
    board.display(writer) catch return;
    writer.flush() catch return;

    const start_time = std.Io.Timestamp.now(init.io, .awake);
    const solution = solver.solve(board, heuristic);
    const duration = start_time.untilNow(init.io, .awake);
    const elapsed = @as(f64, @floatFromInt(duration.toNanoseconds())) / std.time.ns_per_ms;

    max_time = @max(max_time, elapsed);
    total_time += elapsed;

    writer.print("Solution length: {} - Time elapsed: {d}ms\n", .{
      solution.len,
      elapsed
    }) catch return;
    writer.flush() catch return;
  }

  writer.print("Longest time: {d}ms\n", .{ max_time }) catch return;
  writer.print("Average time: {d}ms\n", .{ total_time / TOTAL_GAMES }) catch return;
  writer.flush() catch return;
}
