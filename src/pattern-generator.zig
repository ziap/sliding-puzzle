const std = @import("std");

const Pcg32 = @import("Pcg32.zig");
const Board = @import("Board.zig");

const common = @import("common.zig");

const PatternDatabase = @import("PatternDatabase.zig");

const Cost = Board.Cost;
const MAX_COST = Board.MAX_COST;

const PDBGenerator = struct {
  const SIZE = 16 * 15 * 14 * 13 * 12;
  const HASH_BITS = 20;
  const HASH_SIZE = 1 << HASH_BITS;

  const HashIndex = common.Uint(HASH_BITS);

  pdb: *PatternDatabase,
  frontiers: [3]common.StaticList(Board, SIZE),
  hash_table: [HASH_SIZE]Board,

  fn init(self: *PDBGenerator, pdb: *PatternDatabase) void {
    self.pdb = pdb;
    self.pdb.init();
  }

  fn index(self: *PDBGenerator, board: Board) *Board {
    var h = board.hash(HASH_BITS);
    var ptr = &self.hash_table[h];

    while (ptr.data != Board.invalid.data and ptr.data != board.data) {
      h +%= 1;
      ptr = &self.hash_table[h];
    }

    return ptr;
  }

  fn processPattern(self: *PDBGenerator, board: Board, dummy: u64, comptime exclude_empty: bool) void {
    var frontier = &self.frontiers[0];
    var next_frontier = &self.frontiers[1];
    var next_frontier_not_moved = &self.frontiers[2];

    @memset(&self.hash_table, Board.invalid);

    frontier.len = 0;
    frontier.push(board);
    self.index(board).* = board;

    var depth: Cost = 0;

    while (frontier.len > 0) {
      for (frontier.view()) |current| {
        _ = self.pdb.tryInsertPattern(current, dummy, depth, exclude_empty);
        const moves = current.getMoves(Board.invalid);

        for (moves.view()) |next| {
          if (self.index(next).data == Board.invalid.data) {
            const changed = ((next.data ^ current.data) >> next.emptyPos()) & 0xf;
            if (changed == dummy) {
              next_frontier_not_moved.push(next);
            } else {
              next_frontier.push(next);
            }
          }
        }
      }

      frontier.len = 0;
      if (next_frontier_not_moved.len > 0) {
        for (next_frontier_not_moved.view()) |next| {
          const ptr = self.index(next);
          if (ptr.data == Board.invalid.data) {
            ptr.* = next;
            frontier.push(next);
          }
        }
        next_frontier_not_moved.len = 0;
      } else {
        for (next_frontier.view()) |next| {
          const ptr = self.index(next);
          if (ptr.data == Board.invalid.data) {
            ptr.* = next;
            frontier.push(next);
          }
        }
        next_frontier.len = 0;
        depth += 1;
      }
    }
  }
};

fn Combinations(N: comptime_int, K: comptime_int) type {
  return struct {
    const Item = common.UintFit(N);

    idx: usize,
    data: [K]Item,

    fn next(self: *@This()) ?*const [K]Item {
      return while (self.idx < K) {
        if (self.data[self.idx] < N) {
          self.data[self.idx] += 1;
          if (self.idx < K - 1) {
            self.idx += 1;
            self.data[self.idx] = self.data[self.idx - 1];
          } else {
            break &self.data;
          }
        } else {
          self.idx -%= 1;
        }
      } else null;
    }
  };
}

fn combinations(N: comptime_int, K: comptime_int) Combinations(N, K) {
  return .{ .idx = 0, .data = .{ 0 } ** K };
}

fn tilesToPattern(tiles: anytype) struct { Board, u64 } {
  const mask = blk: {
    var mask: u32 = 1;
    inline for (tiles) |tile| {
      mask |= @as(u32, 1) << tile;
    }
    break :blk mask;
  };

  const dummy: u64 = @intCast(@ctz(~mask & (mask + 1)));

  const initial = Board.initial;
  var board: Board = .{ .data = 0 };
  inline for (0..16) |i| {
    const shift = i * 4;

    const tile = (initial.data >> shift) & 0xf;
    if ((mask >> tile) & 1 == 1) {
      board.data |= tile << shift; 
    } else {
      board.data |= dummy << shift;
    }
  }

  return .{ board, dummy };
}

var database: PatternDatabase = undefined;

pub fn main() !void {
  var line: [128]u8 = undefined;
  var line_len: usize = 1;
  var writer = std.io.getStdOut().writer();

  const file_path = "patterns.bin";

  if (std.fs.cwd().openFile(file_path, .{})) |file| {
    _ = try file.readAll(database.asBytes());
  } else |err| {
    if (err != error.FileNotFound) return err;

    const S = struct {
      var pdb_gen: PDBGenerator = undefined;
    };
    S.pdb_gen.init(&database);

    {
      var comb = combinations(15, 4);
      while (comb.next()) |tiles| {
        const board, const dummy = tilesToPattern(tiles);

        line[0] = '\r';
        @memset(line[1..line_len], ' ');
        const printed = std.fmt.bufPrint(line[line_len..], "\rProcessing: {any}", .{ tiles }) catch &.{};
        writer.writeAll(line[0..line_len + printed.len]) catch return;
        line_len = printed.len;

        S.pdb_gen.processPattern(board, dummy, true);
      }
    }

    writer.writeAll("\n") catch return;

    {
      var comb = combinations(15, 3);
      while (comb.next()) |tiles| {
        const board, const dummy = tilesToPattern(tiles);

        line[0] = '\r';
        @memset(line[1..line_len], ' ');
        const printed = std.fmt.bufPrint(line[line_len..], "\rProcessing: {any}", .{ tiles }) catch &.{};
        writer.writeAll(line[0..line_len + printed.len]) catch return;
        line_len = printed.len;

        S.pdb_gen.processPattern(board, dummy, false);
      }
    }

    writer.writeAll("\n") catch return;

    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();
    try file.writeAll(database.asBytes());
  }
}
