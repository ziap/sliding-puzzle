const common = @import("common.zig");

pub const Cost = u8;
pub const MAX_COST = -% @as(Cost, 1);

// Bitboard representation of the sliding puzzle
const Board = @This();

// Every tile is in the range 0 -> 15, where 0 denotes the empty tile
// This makes the entire board takes up 4 * 16 = 64 bits of memory
data: u64,

pub const initial: Board = .{ .data = 0x0FEDCBA987654321 };

// Any board that can't be reached from the initial state works.
pub const invalid: Board = .{ .data = 0 };

pub const MoveList = common.StaticList(Board, 4);

pub fn solved(self: Board) bool {
  return self.data == initial.data;
}

// Generate a board by repeatedly moving in random directions
// This is useful for creating easy puzzles
pub fn randomMoves(rng: anytype, random_moves: anytype) Board {
  comptime {
    const T = @TypeOf(random_moves);
    switch (@typeInfo(T)) {
      .Int, .ComptimeInt => {},
      else => {
        const msg = "Expected integer argument, found: " ++ @typeName(T);
        @compileError(msg);
      },
    }
  }

  var last = invalid;
  var board = initial;

  for (0..random_moves) |_| {
    const moves = board.getMoves(last);
    last = board;
    board = moves.buf[rng.bounded(moves.len)];
  }

  return board;
}

// Generate a uniformly distributed board by generating a random permutation
pub fn randomUniform(rng: anytype) Board {
  const data = blk: {
    // Generate the identity permutation
    var perm = comptime blk_perm: {
      var perm: [16]u4 = undefined;
      for (&perm, 0..) |*pos, idx| {
        pos.* = idx;
      }

      break :blk_perm perm;
    };

    // Fisher–Yates shuffle the identity permutation
    var data: u64 = 0;
    inline for (perm[0..15], 0..) |tile, idx| {
      const remaining = perm[idx..];
      const other = &remaining[rng.bounded(remaining.len)];
      data <<= 4;
      data |= other.*;
      other.* = tile;
    }

    break :blk data << 4 | perm[perm.len - 1];
  };

  const board: Board = .{ .data = data };
  if (board.solvable()) return board;

  // If the board is unsolvable, a bijective mapping from unsolvable boards
  // to solvable boards is applied.
  return .{
    .data = ((data & 0xffff000000000000) >> 48)
          | ((data & 0x0000ffff00000000) >> 16)
          | ((data & 0x00000000ffff0000) << 16)
          | ((data & 0x000000000000ffff) << 48)
  };
}

pub fn emptyPos(self: Board) u6 {
  var b = self.data;
  b |= (b >> 2) & 0x3333333333333333;
  b |= (b >> 1);
  return @intCast(@ctz(~b & 0x1111111111111111));
}

// Fast 4x4x4 bitboard transposition that I stole somewhere 6 years ago. If I
// ever find the source again I'll put it here.
pub fn transpose(self: Board) Board {
  var x = self.data;
  var b = (x ^ (x >> 12)) & 0x0000f0f00000f0f0;
  x ^= b ^ (b << 12);
  b = (x ^ (x >> 24)) & 0x00000000ff00ff00;
  x ^= b ^ (b << 24);
  return .{ .data = x };
}

fn inversions(self: Board) u32 {
  var b = self.data;
  var inv: u32 = 0;

  inline for (0..15) |idx| {
    const tile = b & 0xf;
    b >>= 4;

    var t = b;
    inline for (idx + 1..16) |_| {
      const other = t & 0xf;
      if (tile != 0 and other != 0 and tile > other) inv += 1;
      t >>= 4;
    }
  }

  return inv;
}

// Check if a puzzle configuration is solvable using permutation parity.
// TODO: Speed up the computation and use it as a heuristic
pub fn solvable(self: Board) bool {
  return (self.inversions() + (self.emptyPos() >> 4)) & 1 == 1;
}

// Move generation using bitwise operations. The main idea is to use XOR to
// swap the empty tile with its neighboring tiles.
pub fn getMoves(self: Board, last: Board) MoveList {
  const board = self.data;

  const empty = self.emptyPos();
  const empty_row = empty >> 4;
  const empty_col = empty & 0xf;

  var moves: MoveList = .{};

  if (empty_row < 3) {
    const pos = empty + 16;
    const mask = (board >> pos) & 0xf;
    const up = board ^ (((mask << 16) | mask) << empty);

    if (up != last.data) moves.push(.{ .data = up });
  }

  if (empty_row > 0) {
    const pos = empty - 16;
    const mask = (board >> pos) & 0xf;
    const down = board ^ (((mask << 16) | mask) << pos);

    if (down != last.data) moves.push(.{ .data = down });
  }

  if (empty_col < 12) {
    const pos = empty + 4;
    const mask = (board >> pos) & 0xf;
    const left = board ^ (((mask << 4) | mask) << empty);

    if (left != last.data) moves.push(.{ .data = left });
  }

  if (empty_col > 0) {
    const pos = empty - 4;
    const mask = (board >> pos) & 0xf;
    const right = board ^ (((mask << 4) | mask) << pos);

    if (right != last.data) moves.push(.{ .data = right });
  }

  return moves;
}

// A commonly used admissible heuristic for solving the puzzle with A*
pub const ManhattanHeuristic = struct {
  pub fn evaluate(self: Board) Cost {
    // Precompute the manhattan distance for every tile on every position
    const S = struct {
      const cost_table = blk: {
        var res: [16][16]Cost = undefined;

        var goal_pos: [15]@Vector(2, i8) = undefined;
        for (&goal_pos, 0..) |*pos, idx| {
          pos.*= .{ idx / 4, idx % 4 };
        }

        for (&res, 0..) |*cost, cost_idx| {
          // Counting the empty tile will cause overestimation
          cost[0] = 0;

          const pos: @Vector(2, i8) = .{ cost_idx / 4, cost_idx % 4 };
          for (cost[1..], 0..) |*tile, tile_idx| {
            const x, const y = @abs(pos - goal_pos[tile_idx]);
            tile.* = x + y;
          }
        }

        break :blk res;
      };
    };

    var result: Cost = 0;
    var b = self.data;
    inline for (S.cost_table) |cost| {
      result += cost[b & 0xf];
      b >>= 4;
    }

    return result;
  }
};

// Pretty-print the board for debug and demonstration purposes
pub fn display(self: Board, writer: anytype) !void {
  const digits = comptime blk: {
    var digits: [16][2]u8 = undefined;

    digits[0] = "  ".*;

    for (1..10) |i| {
      digits[i] = " ".* ++ .{ '0' + i };
    }

    for (10..16) |i| {
      digits[i] = .{ '0' + (i / 10), '0' + (i % 10) };
    }

    break :blk digits;
  };

  try writer.writeAll("+----+----+----+----+\n");

  var b = self.data;

  inline for (0..4) |_| {
    inline for (0..4) |_| {
      try writer.writeAll("| ");
      try writer.writeAll(&digits[b & 0xf]);
      try writer.writeAll(" ");

      b >>= 4;
    }

    try writer.writeAll("|\n+----+----+----+----+\n");
  }
}

// Lehmer64 PRNG hash function, a very fast but weak hash function that
// comphensate its speed for some extra collisions
pub fn hash(self: Board, bits: comptime_int) common.Uint(bits) {
  // MCG multiplier from: <https://arxiv.org/pdf/2001.05304>
  const h = self.data *% 0xf1357aea2e62a9c5;

  // I use shift instead of truncation because the high bits have better
  // statistical quality
  return @intCast(h >> (64 - bits));
}
