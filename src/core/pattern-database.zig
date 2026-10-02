const Board = @import("Board.zig");
const common = @import("common.zig");

const MAX_COST = Board.MAX_COST;

// A patch of a board that can be used to index into a database
fn Pattern(pattern: []const u4) type {
  return struct {
    comptime {
      if (@popCount(BITSET) != pattern.len) {
        @compileError("Pattern contains duplicate tiles");
      }
    }

    // The size of the database is the number of arrangement of the tiles in
    // the pattern, which is k-permutations of n, where k is the size of the
    // pattern and n is the size of the board (16)
    const SIZE = blk: {
      var res = 1;
      for (17 - pattern.len..17) |idx| {
        res *= idx;
      }

      break :blk res;
    };

    // The pattern in a bitset representation to quickly check if a tile is
    // part in the pattern
    const BITSET = blk: {
      var res: u16 = 0;
      for (pattern) |tile| res |= (1 << tile);

      break :blk res;
    };

    const DBIndex = u32;
    const PatternType = @This();

    // Extract the pattern from the board and returns an index
    fn index(board: Board) DBIndex {
      const shifts = blk: {
        const pos_map = comptime blk_pos_map: {
          var res: [16]u4 = .{pattern.len} ** 16;

          for (pattern, 0..) |tile, idx| res[tile] = idx;

          break :blk_pos_map res;
        };

        var shifts: [pattern.len + 1]u16 = undefined;

        // Extracting the position of tiles in the pattern shift 1 by it to use
        // in a bitset during the Lehmer code construction
        var b = board.data;
        inline for (0..16) |pos| {
          shifts[pos_map[@intCast(b & 0xf)]] = @as(u16, 1) << pos;
          b >>= 4;
        }

        break :blk shifts;
      };

      // Constructing a Lehmer code from the arrangement of the tiles
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

    // Moving a non-pattern tile costs nothing, so every board where the blank
    // is anywhere in its region of free cells has the same cost. Assign the
    // cost to the whole region at once and queue all of them for expansion.
    fn fillRegion(
      database: []Board.Cost,
      list: anytype,
      board: Board,
      depth: Board.Cost,
    ) void {
      // Tiles the blank can swap with without changing the cost: the blank
      // itself and every non-pattern tile
      const FREE_TILES = ~BITSET | 1;

      // Masks for the first and last column of a 4x4 cell bitset
      const MASK_FIRST = ~@as(u16, 0x1111);
      const MASK_LAST  = ~@as(u16, 0x8888);

      var free: u16 = 0;
      var b = board.data;
      inline for (0..16) |cell| {
        if (FREE_TILES & (@as(u16, 1) << @intCast(b & 0xf)) != 0) {
          free |= 1 << cell;
        }
        b >>= 4;
      }

      // Flood fill from the blank through the free cells
      const empty = board.emptyPos();
      var region = @as(u16, 1) << @intCast(empty / 4);
      inline for (0..16 - pattern.len) |_| {
        const grown = free & (
            region
          | (region << 4)
          | (region >> 4)
          | ((region << 1) & MASK_FIRST)
          | ((region >> 1) & MASK_LAST)
        );
        region = grown;
      }

      var cells = region;
      while (cells != 0) : (cells &= cells - 1) {
        // Swap the blank with the tile at `pos`, a no-op for the blank itself
        const pos = @as(u6, @ctz(cells)) * 4;
        const tile = (board.data >> pos) & 0xf;
        const moved: Board = .{
          .data = board.data ^ (tile << empty) ^ (tile << pos),
        };

        // Regions are always assigned as a whole
        const idx = index(moved);
        if (database[idx] != MAX_COST) unreachable;

        database[idx] = depth;
        list.push(moved);
      }
    }

    // Performs breadth-first search to fill up the pattern database
    fn search(database: []Board.Cost, buffer: []Board) void {
      @memset(database, MAX_COST);

      var frontier = common.sliceList(Board, buffer[0..SIZE]);
      var next_frontier = common.sliceList(Board, buffer[SIZE..2 * SIZE]);

      frontier.len = 0;
      next_frontier.len = 0;

      // Add the initial board to the database
      var depth: Board.Cost = 0;
      fillRegion(database, &frontier, .initial, 0);

      while (frontier.len > 0) : (depth += 1) {
        while (frontier.pop()) |board| {
          const moves = board.getMoves(Board.invalid, false);
          for (moves.view()) |next| {
            const empty_pos = next.emptyPos();
            const moved: u4 = @truncate((board.data ^ next.data) >> empty_pos);

            // Non-pattern tile moved
            if (BITSET & (@as(u16, 1) << moved) == 0) continue;

            // Already reached
            const idx = index(next);
            if (database[idx] < MAX_COST) continue;

            fillRegion(database, &next_frontier, next, depth + 1);
          }
        }

        // Swap the buffers, set the next frontier as the current frontier and
        // reuse the current frontier's memory as to build the next frontier
        const tmp = frontier;
        frontier = next_frontier;
        next_frontier = tmp;
      }
    }
  };
}

// Disjoint pattern database heuristics
pub fn PDBHeuristic(patterns: []const []const u4) type {
  return struct {
    const PatternTypes = blk: {
      var results: [patterns.len]type = undefined;

      for (&results, patterns) |*result, pattern| {
        // Add the empty tile to the pattern
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

    // The buffer used during the construction of the pattern database
    pub const ScratchBuffer = blk: {
      var max_size: comptime_int = 0;

      for (PatternTypes) |PatternType| {
        max_size = @max(max_size, PatternType.SIZE);
      }

      break :blk [max_size * 2]Board;
    };

    pub const Database = [TOTAL_SIZE]Board.Cost;
    database: *Database,

    const Heuristic = @This();

    // Incremental cost model used by the search algorithms, the cost of a
    // board is derived from the cost of its parent
    pub const Cost = struct {
      value: Board.Cost,

      // Currently evaluates the moved board from scratch
      pub fn update(
        self: Cost,
        heuristic: Heuristic,
        board: Board,
        moved: Board,
      ) Cost {
        _ = self;
        _ = board;
        return .{ .value = heuristic.evaluate(moved) };
      }

      pub fn get(self: Cost) Board.Cost {
        return self.value;
      }
    };

    pub fn cost(self: Heuristic, board: Board) Cost {
      return .{ .value = self.evaluate(board) };
    }

    pub fn generate(self: @This(), buffer: *ScratchBuffer) void {
      var view: []Board.Cost = self.database;

      inline for (PatternTypes) |PatternType| {
        PatternType.search(view, buffer);
        view = view[PatternType.SIZE..];
      }
    }

    pub fn evaluate(self: @This(), board: Board) Board.Cost {
      var view: []const Board.Cost = self.database;
      var result: Board.Cost = 0;
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
// _ _ _ _  # _ _ _  _ # # _

pub const PatternDatabase555 = PDBHeuristic(&.{
  &.{2, 3, 4, 6, 7},
  &.{8, 11, 12, 14, 15},
  &.{1, 5, 9, 10, 13},
});

// # # # #  _ _ _ _  _ _ _ _
// _ # # _  # _ _ _  _ _ _ #
// _ _ _ _  # _ _ _  _ # # #
// _ _ _ _  # _ _ _  _ # # _

pub const PatternDatabase663 = PDBHeuristic(&.{
  &.{1, 2, 3, 4, 6, 7},
  &.{8, 10, 11, 12, 14, 15},
  &.{5, 9, 13},
});

// # # # #  _ _ _ _  _ _ _ _
// _ # # _  # _ _ _  _ _ _ #
// _ _ _ _  # # _ _  _ _ # #
// _ _ _ _  # _ _ _  _ # # _

// Hybrid partition inspired from the last two
pub const PatternDatabase654 = PDBHeuristic(&.{
  &.{1, 2, 3, 4, 6, 7},
  &.{8, 11, 12, 14, 15},
  &.{5, 9, 10, 13},
});

// # # # #  _ _ _ _
// # # # #  _ _ _ _
// _ _ _ _  # # # #
// _ _ _ _  # # # _

pub const PatternDatabase87 = PDBHeuristic(&.{
  &.{1, 2, 3, 4, 5, 6, 7, 8},
  &.{9, 10, 11, 12, 13, 14, 15},
});

// TODO: Use "b.addOptions" to dynamically select pattern database
pub const Default = PatternDatabase654;
