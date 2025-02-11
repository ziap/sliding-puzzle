const Board = @import("Board.zig");
const common = @import("common.zig");
const Cost = Board.Cost;
const MAX_COST = Board.MAX_COST;

fn Pattern(pattern: []const u4) type {
  return struct {
    comptime {
      if (@popCount(BITMAP) != pattern.len) {
        @compileError("Pattern contains duplicate tiles");
      }
    }

    const SIZE = blk: {
      var res = 1;
      for (17 - pattern.len..17) |idx| {
        res *= idx;
      }

      break :blk res;
    };

    const BITMAP = blk: {
      var res: u16 = 0;
      for (pattern) |tile| res |= (1 << tile);

      break :blk res;
    };

    const DBIndex = u32;
    const PatternType = @This();

    fn index(board: Board) DBIndex {
      const S = struct {
        const pos_map = blk: {
          var res: [16]u4 = .{pattern.len} ** 16;

          for (pattern, 0..) |tile, idx| res[tile] = idx;

          break :blk res;
        };
      };

      const shifts = blk: {
        var shifts: [pattern.len + 1]u16 = undefined;

        var b = board.data;
        inline for (0..16) |pos| {
          shifts[S.pos_map[b & 0xf]] = @as(u16, 1) << pos;
          b >>= 4;
        }

        break :blk shifts;
      };

      var idx: DBIndex = 0;
      var remaining_count: u5 = 16;
      var remaining: u16 = 0xffff;
      inline for (shifts[0..pattern.len]) |shift| {
        idx = idx * remaining_count + @popCount(remaining & (shift - 1));
        remaining ^= shift;
        remaining_count -= 1;
      }

      return idx;
    }

    fn search(database: []Cost, allocator: anytype) !void {
      @memset(database, MAX_COST);

      const buf = try allocator.alloc(common.StaticList(Board, SIZE), 3);
      defer allocator.free(buf);

      var frontier = &buf[0];
      var next_frontier_moved = &buf[1];
      var next_frontier = &buf[2];

      var depth: Cost = 0;
      frontier.len = 0;
      {
        const board = Board.initial;
        const idx = index(board);
        database[idx] = 0;
        frontier.push(board);
      }

      next_frontier.len = 0;
      next_frontier_moved.len = 0;

      while (frontier.len > 0) {
        for (frontier.view()) |board| {
          const moves = board.getMoves(Board.invalid);
          for (moves.view()) |next| {
            const empty_pos = next.emptyPos();
            if (database[index(next)] != MAX_COST) continue;
            const moved_tile: u4 = @truncate((board.data ^ next.data) >> empty_pos);

            if (BITMAP & (@as(u16, 1) << moved_tile) != 0) {
              next_frontier_moved.push(next);
            } else {
              next_frontier.push(next);
            }
          }
        }

        frontier.len = 0;
        if (next_frontier.len > 0) {
          for (next_frontier.view()) |board| {
            const idx = index(board);
            if (database[idx] == MAX_COST) {
              database[idx] = depth;
              frontier.push(board);
            }
          }
          next_frontier.len = 0;
        } else {
          for (next_frontier_moved.view()) |board| {
            const idx = index(board);
            if (database[idx] == MAX_COST) {
              database[idx] = depth;
              frontier.push(board);
            }
          }
          next_frontier_moved.len = 0;
          depth += 1;
        }
      }
    }

  };
}

pub fn PDBHeuristic(patterns: []const []const u4) type {
  return struct {
    const PatternTypes = blk: {
      var results: [patterns.len]type = undefined;

      for (&results, patterns) |*result, pattern| {
        result.* = Pattern(.{0} ++ pattern);
      }

      break :blk results;
    };

    pub const TOTAL_SIZE = blk: {
      var result = 0;
      for (PatternTypes) |PatternType| {
        result += PatternType.SIZE;
      }
      break :blk result;
    };

    database: [TOTAL_SIZE]Cost,

    pub fn generate(self: *@This(), allocator: anytype) !void {
      const std = @import("std");

      var arena = std.heap.ArenaAllocator.init(allocator);
      defer arena.deinit();

      var view: []Cost = &self.database;

      inline for (PatternTypes) |PatternType| {
        _ = arena.reset(.retain_capacity);
        try PatternType.search(view, arena.allocator());
        view = view[PatternType.SIZE..];
      }
    }

    pub fn evaluate(self: *const @This(), board: Board) Cost {
      var view: []const Cost = self.database[0..];
      var result: Cost = 0;
      inline for (PatternTypes) |PatternType| { 
        result += view[PatternType.index(board)];
        view = view[PatternType.SIZE..];
      }
      return result;
    }
  };
}

// Board partition from: <https://arxiv.org/pdf/1107.0050>

//  1  2  3  4
//  5  6  7  8
//  9 10 11 12
// 13 14 15 0

// _ # # #  # _ _ _  _ _ _ _
// _ # # _  # _ _ _  _ _ _ #
// _ _ _ _  # # _ _  _ _ # #
// _ _ _ _  # _ _ _  _ # #

pub const PatternDatabase555 = PDBHeuristic(&.{
  &.{2, 3, 4, 6, 7},
  &.{8, 11, 12, 14, 15},
  &.{1, 5, 9, 10, 13},
});

// # # # #  _ _ _ _  _ _ _ _
// _ # # _  # _ _ _  _ _ _ #
// _ _ _ _  # _ _ _  _ # # #
// _ _ _ _  # _ _ _  _ # #

pub const PatternDatabase663 = PDBHeuristic(&.{
  &.{1, 2, 3, 4, 6, 7},
  &.{8, 10, 11, 12, 14, 15},
  &.{5, 9, 13},
});

// # # # #  _ _ _ _  _ _ _ _
// _ # # _  # _ _ _  _ _ _ #
// _ _ _ _  # # _ _  _ _ # #
// _ _ _ _  # _ _ _  _ # #

// Hybrid partition inspired from the last two
pub const PatternDatabase654 = PDBHeuristic(&.{
  &.{1, 2, 3, 4, 6, 7},
  &.{8, 11, 12, 14, 15},
  &.{5, 9, 10, 13},
});

// TODO: Use the build system to dynamically select pattern database
pub const Default = PatternDatabase555;
