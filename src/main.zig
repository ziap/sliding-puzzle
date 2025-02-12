const std = @import("std");

const Pcg32 = @import("Pcg32.zig");
const Board = @import("Board.zig");

const Solver = @import("solver.zig").HybridSolver;

const Cost = Board.Cost;
const MAX_COST = Board.MAX_COST;

const Heuristic = @import("pattern-database.zig").Default;

pub fn main() !void {
  var buffer = std.io.bufferedWriter(std.io.getStdOut().writer());
  defer buffer.flush() catch {};
  var writer = buffer.writer();

  var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
  defer arena.deinit();
  const allocator = arena.allocator();

  var solver = try allocator.create(Solver);
  
  var rng = Pcg32.withSeed(1337);

  const heuristic = blk: {
    const heuristic = try allocator.create(Heuristic);

    const FILE_PATH = "patterns.gz";
    const compressed_file = std.fs.cwd().openFile(FILE_PATH, .{}) catch |err| {
      std.debug.print("Error: Failed to open `{s}`: {}\n", .{ FILE_PATH, err });
      return;
    };
    defer compressed_file.close();
    const compressed_reader = compressed_file.reader();

    var decompress_stream = std.io.fixedBufferStream(&heuristic.database);
    var decompress_writer = decompress_stream.writer();

    std.compress.flate.decompress(compressed_reader, &decompress_writer) catch |err| {
      std.debug.print("Error: Failed to decompress `{s}`: {}\n", .{ FILE_PATH, err });
      return;
    };

    if (!heuristic.checkIntegrity()) {
      std.debug.print("Error: Pattern database corrupted\n", .{});
      return;
    }

    break :blk heuristic;
  };

  var max_time: f64 = 0;
  var total_time: f64 = 0;

  const TOTAL_GAMES = 400;

  for (0..TOTAL_GAMES) |_| {
    const board = Board.randomUniform(&rng);
    board.display(&writer) catch return;
    buffer.flush() catch return;

    var timer = try std.time.Timer.start();
    const solution = solver.solve(board, heuristic);
    const elapsed = @as(f64, @floatFromInt(timer.read())) / std.time.ns_per_ms;

    max_time = @max(max_time, elapsed);
    total_time += elapsed;

    writer.print("Solution length: {} - Time elapsed: {d}ms\n", .{
      solution.len,
      elapsed
    }) catch return;
    buffer.flush() catch return;
  }

  writer.print("Longest time: {d}ms\n", .{ max_time }) catch return;
  writer.print("Average time: {d}ms\n", .{ total_time / TOTAL_GAMES }) catch return;
}
