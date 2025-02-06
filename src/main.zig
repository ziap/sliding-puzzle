const std = @import("std");

const Pcg32 = @import("Pcg32.zig");
const Board = @import("Board.zig");

const Solver = @import("solver.zig").HybridSolver;

const Cost = Board.Cost;
const MAX_COST = Board.MAX_COST;

// Tested seeds and their move count
// 0x7a6170 -> 60

var solver: Solver = undefined;

pub fn main() !void {
  var buffer = std.io.bufferedWriter(std.io.getStdOut().writer());
  var writer = buffer.writer();
  
  var rng = Pcg32.withSeed(1337);

  for (0..3) |_| {
    const board = Board.randomUniform(&rng);
    try board.display(&writer);
    try buffer.flush();

    var timer = try std.time.Timer.start();
    const solution = solver.solve(board);
    const elapsed: f64 = @floatFromInt(timer.read());

    try writer.print("Solution length: {} - Time elapsed: {d}\n", .{
      solution.len,
      elapsed / std.time.ns_per_s,
    });
    try buffer.flush();
  }
  
  try buffer.flush();
}
