const Board = @import("Board.zig");
const common = @import("common.zig");

const Cost = Board.Cost;
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

    // Will be used for the construction of the pattern database
    const Stacks = [2]common.StaticList(Board, SIZE);

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
          shifts[pos_map[b & 0xf]] = @as(u16, 1) << pos;
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

    // Performs breadth-first search to fill up the pattern database
    fn search(database: []Cost, buffer: *Stacks) void {
      @memset(database, MAX_COST);

      var frontier = &buffer[0];
      var next_frontier = &buffer[1];

      frontier.len = 0;
      next_frontier.len = 0;

      // Add the initial board to the database
      var depth: Cost = 0;
      frontier.push(Board.initial);
      database[index(Board.initial)] = 0;

      while (frontier.len > 0) : (depth += 1) {
        while (frontier.pop()) |board| {
          // The board is reached earlier, don't bother expanding its children
          if (database[index(board)] < depth) continue;

          const moves = board.getMoves(Board.invalid, false);
          for (moves.view()) |next| {
            const empty_pos = next.emptyPos();
            const moved: u4 = @truncate((board.data ^ next.data) >> empty_pos);
            const idx = index(next);

            if (BITSET & (@as(u16, 1) << moved) != 0) {
              // A pattern tile is moved, insert it to the next frontier list
              if (database[idx] <= depth + 1) continue;

              database[idx] = depth + 1;
              next_frontier.push(next);
            } else {
              // A non-pattern tile is moved, insert it back into the current
              // frontier list
              if (database[idx] <= depth) continue;

              database[idx] = depth;
              frontier.push(next);
            }
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
      const Type = @import("std").builtin.Type;

      var fields: [patterns.len]Type.UnionField = undefined;
      
      for (PatternTypes, &fields) |PatternType, *field| {
        const Stacks = PatternType.Stacks;

        field.* = .{
          .name = @typeName(PatternType),
          .type = Stacks,
          .alignment = @alignOf(Stacks),
        };
      }
      
      break :blk @Type(.{
        .Union = .{
          .layout = .auto,
          .tag_type = null,
          .fields = &fields,
          .decls = &.{},
        },
      });
    };

    database: [TOTAL_SIZE]Cost align(@alignOf(u64)),

    pub fn generate(self: *@This(), buffer: *ScratchBuffer) void {
      var view: []Cost = &self.database;

      inline for (PatternTypes) |PatternType| {
        PatternType.search(view, &@field(buffer, @typeName(PatternType)));
        view = view[PatternType.SIZE..];
      }
    }

    const Checksum = [@sizeOf(u64)]u8;

    // Generate a checksum for integrity checking using a non-cryptographic
    // hash function inspird by: <https://github.com/orlp/foldhash>
    pub fn checksum(self: *const @This()) Checksum {
      const is_le = comptime blk: {
        const native_endian = @import("builtin").cpu.arch.endian();
        break :blk native_endian == .little;
      };

      const mum = struct {
        // Multiply-and-mix operation commonly used in wyhash, xxhash, etc.
        fn inner(x: u64, y: u64) u64 {
          const m = @as(u128, x) *% @as(u128, y);

          const hi: u64 = @intCast(m >> 64);
          const lo: u64 = @truncate(m);

          return hi ^ lo;
        }
      }.inner;

      // Split the memory into chunks of u64 pairs
      const Chunks = *const [TOTAL_SIZE / (@sizeOf(u64) * 2)][2]u64;
      const chunks: Chunks = @ptrCast(&self.database);

      // A good half-width 128-bit MCG multiplier used in PCG64-DXSM
      const m = 0xda942042e4dd58b5;

      var h: u64 = mum(TOTAL_SIZE, m);
      for (chunks) |chunk| {
        // Use little endian during computation for faster fetch on x86_64
        const a = if (comptime is_le) chunk[0] else @byteSwap(chunk[0]);
        const b = if (comptime is_le) chunk[1] else @byteSwap(chunk[1]);

        // Xor with a random constant to avoid trivial zero collapse
        h = mum(h ^ a, 0x9e3779b97f4a7c15 ^ b);
      }

      // Finalization step to avalanche the bits
      h = mum(h, m);

      // Export the checksum as bytes in big endian for storage
      const result = if (comptime is_le) @byteSwap(h) else h;
      return @bitCast(result);
    }

    pub fn checkIntegrity(self: *const @This()) bool {
      // Load the correct checksum and converts it to u64 for comparison
      const correct: u64 = comptime blk: {
        const correct_file: *const Checksum = @embedFile("patterns.chk");
        break :blk @bitCast(correct_file.*);
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
pub const Default = PatternDatabase555;
