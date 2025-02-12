const std = @import("std");
const Board = @import("Board.zig");

const Heuristic = @import("pattern-database.zig").Default;
const ManhattanHeuristic = Board.ManhattanHeuristic;

pub fn main() !void {
  const allocator = std.heap.page_allocator;

  const heuristic = try allocator.create(Heuristic);
  defer allocator.destroy(heuristic);

  std.debug.print("Generating the pattern database\n", .{});
  try heuristic.generate(allocator);

  {
    std.debug.print("Exporting the pattern database\n", .{});
    const compressed_file = try std.fs.cwd().createFile("patterns.gz", .{});
    defer compressed_file.close();
    const compressed_writer = compressed_file.writer();

    var data_stream = std.io.fixedBufferStream(&heuristic.database);
    var data_reader = data_stream.reader();

    try std.compress.flate.compress(&data_reader, compressed_writer, .{
      .level = .best
    });
  }

  {
    std.debug.print("Exporting the checksum\n", .{});
    const checksum_file = try std.fs.cwd().createFile("src/patterns.chk", .{});
    defer checksum_file.close();
    try checksum_file.writeAll(&heuristic.checksum());
  }
}
