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
    const compressed_file = try std.fs.cwd().createFile("patterns.gz", .{});
    defer compressed_file.close();
    const compressed_writer = compressed_file.writer();

    var data_stream = std.io.fixedBufferStream(&S.heuristic.database);
    var data_reader = data_stream.reader();

    try std.compress.flate.compress(&data_reader, compressed_writer, .{
      .level = .best
    });
  }

  {
    std.debug.print("Exporting the checksum\n", .{});
    const checksum_file = try std.fs.cwd().createFile("src/patterns.chk", .{});
    defer checksum_file.close();
    try checksum_file.writeAll(&S.heuristic.checksum());
  }
}
