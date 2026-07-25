const std = @import("std");
const Board = @import("Board.zig");

const Heuristic = @import("pattern-database.zig").Default;

pub fn main(init: std.process.Init) !void {
  const allocator = init.arena.allocator();

  const database = try allocator.create(Heuristic.Database);
  const buffer = try allocator.create(Heuristic.ScratchBuffer);

  const heuristic: Heuristic = .{ .database = database };

  const start_time = std.Io.Timestamp.now(init.io, .awake);
  std.debug.print("Generating the pattern database\n", .{});
  heuristic.generate(buffer);

  const duration = start_time.untilNow(init.io, .awake);
  const elapsed = @as(f64, @floatFromInt(duration.toNanoseconds())) / std.time.ns_per_ms;
  std.debug.print("Generated the pattern database in: {d}ms\n", .{ elapsed });

  {
    std.debug.print("Exporting the pattern database\n", .{});
    const out_file = try std.Io.Dir.cwd().createFile(init.io, "patterns.bin", .{});
    defer out_file.close(init.io);

    try out_file.writePositionalAll(init.io, database, 0);
  }
}
