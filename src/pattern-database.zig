const Board = @import("Board.zig");
const common = @import("common.zig");

const native_endian = @import("builtin").cpu.arch.endian();

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

      const QueueIndex = common.UintFit(SIZE + 1);
      const QUEUE_SIZE = @as(comptime_int, (-% @as(QueueIndex, 1))) + 1;

      var frontier = try allocator.alloc(Board, QUEUE_SIZE);
      defer allocator.free(frontier);

      var next_frontier = try allocator.create(common.StaticList(Board, SIZE));
      defer allocator.destroy(next_frontier);

      var depth: Cost = 0;
      var frontier_start: QueueIndex = 0;
      var frontier_end: QueueIndex = 1;
      frontier[0] = Board.initial;
      database[index(Board.initial)] = 0;

      while (frontier_end != frontier_start) {
        while (frontier_end != frontier_start) {
          const board = frontier[frontier_start];
          frontier_start +%= 1;

          const moves = board.getMoves(Board.invalid);
          for (moves.view()) |next| {
            const empty_pos = next.emptyPos();
            const moved_tile: u4 = @truncate((board.data ^ next.data) >> empty_pos);
            const idx = index(next);

            if (BITMAP & (@as(u16, 1) << moved_tile) != 0) {
              if (database[idx] > depth + 1) {
                database[idx] = depth + 1;
                next_frontier.push(next);
              }
            } else {
              if (database[idx] > depth) {
                database[idx] = depth;
                frontier[frontier_end] = next;
                frontier_end +%= 1;
              }
            }
          }
        }

        depth += 1;
        for (next_frontier.view()) |next| {
          if (database[index(next)] == depth) {
            frontier[frontier_end] = next;
            frontier_end +%= 1;
          }
        }

        next_frontier.len = 0;
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

    database: [TOTAL_SIZE]Cost align(8),

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

    pub fn checksum(self: *const @This()) [8]u8 {
      const mix = struct {
        fn inner(v: u64) u64 {
          const x = (v ^ (v >> 23)) *% 0x2127599bf4325c37;
          return x ^ (x >> 47);
        }
      }.inner;

      const m = 0x880355f21e6d1965;

      if (TOTAL_SIZE % 8 != 0) @compileError("Size of pattern database not divisible by 8");
      const chunks: *const [TOTAL_SIZE / 8]u64 = @ptrCast(&self.database);
      var h: u64 = @truncate(TOTAL_SIZE * m);
      for (chunks) |chunk| {
        const v = if (native_endian == .little) chunk else @byteSwap(chunk);
        h = (h ^ mix(v)) *% m;
      }

      h = mix(h);

      const result = if (native_endian == .big) h else @byteSwap(h);
      return @bitCast(result);
    }

    pub fn checkIntegrity(self: *const @This()) bool {
      const correct: u64 = comptime blk_correct: {
        const correct_file: *const [8]u8 = @embedFile("patterns.chk");
        break :blk_correct @bitCast(correct_file.*);
      };

      return @as(u64, @bitCast(self.checksum())) == correct;
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
pub const Default = PatternDatabase663;
