const std = @import("std");
const Board = @import("Board.zig");

const Heuristic = @import("pattern-database.zig").Default;

pub fn main() !void {
  const S = struct {
    var heuristic: Heuristic = undefined;
    var buffer: Heuristic.ScratchBuffer = undefined;
  };

  var timer = try std.time.Timer.start();
  std.debug.print("Generating the pattern database\n", .{});
  S.heuristic.generate(&S.buffer);

  const elapsed = @as(f64, @floatFromInt(timer.read())) / std.time.ns_per_ms;
  std.debug.print("Generated the pattern database in: {d}ms\n", .{ elapsed });

  {
    std.debug.print("Exporting the pattern database\n", .{});
    const out_file = try std.fs.cwd().createFile("patterns.bin", .{});
    defer out_file.close();

    try out_file.writeAll(&S.heuristic.database);
  }
}
