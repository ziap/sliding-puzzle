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
    const compressed_file = try std.fs.cwd().openFile(FILE_PATH, .{});
    defer compressed_file.close();
    const compressed_reader = compressed_file.reader();

    var decompress_stream = std.io.fixedBufferStream(&heuristic.database);
    var decompress_writer = decompress_stream.writer();

    try std.compress.flate.decompress(compressed_reader, &decompress_writer);
    break :blk heuristic;
  };

  var max_time: f64 = 0;

  for (0..400) |_| {
    const board = Board.randomUniform(&rng);
    board.display(&writer) catch return;
    buffer.flush() catch return;

    var timer = try std.time.Timer.start();
    const solution = solver.solve(board, heuristic);
    const elapsed: f64 = @floatFromInt(timer.read());

    max_time = @max(max_time, elapsed);

    writer.print("Solution length: {} - Time elapsed: {d}\n", .{
      solution.len,
      elapsed / std.time.ns_per_s,
    }) catch return;
    buffer.flush() catch return;
  }

  writer.print("Longest time: {d}\n", .{ max_time / std.time.ns_per_s }) catch return;
}
