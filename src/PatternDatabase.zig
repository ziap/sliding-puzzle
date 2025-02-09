const std = @import("std");
const Board = @import("Board.zig");

const Cost = Board.Cost;
const MAX_COST = Board.MAX_COST;

const PatternDatabase = @This();

const dummy_masks = blk: {
  var masks: [16]u64 = undefined;

  for (&masks, 0..) |*mask, tile| {
    mask.* = tile;
    var shift = 4;

    while (shift < @bitSizeOf(u64)) {
      mask.* = (mask.* << shift) | mask.*;
      shift *= 2;
    }
  }

  break :blk masks;
};

database: [2][16][4][65536]Cost,

pub fn asBytes(self: *PatternDatabase) []u8 {
  return std.mem.sliceAsBytes(&self.database);
}

pub fn init(self: *PatternDatabase) void {
  const flatten: *[2 * 16 * 4 * 65536]Cost = @ptrCast(&self.database);
  @memset(flatten, MAX_COST);
}

pub fn tryInsertPattern(self: *PatternDatabase, board: Board, dummy: u64, cost: Cost, comptime exclude_empty: bool) bool {
  var inserted: bool = false;

  for ([_]Board{ board, board.transpose() }, &self.database) |b, *view| {
    const empty_pos = b.emptyPos();

    var data = b.data;
    var mask = data ^ dummy_masks[dummy];
    mask |= (mask >> 2) & 0x3333333333333333;
    mask |= (mask >> 1);
    mask = ~mask & 0x1111111111111111;

    if (exclude_empty) mask ^= @as(u64, 1) << empty_pos;

    if (@popCount(mask) != 12) unreachable;

    inline for (&view[empty_pos >> 2]) |*cost_table| {
      const row = data & 0xffff;
      if (mask & 0xffff == 0x0 and cost_table[row] > cost) {
        cost_table[row] = cost;
        inserted = true;
      }
      data >>= 16;
      mask >>= 16;
    }
  }

  return inserted;
}

pub fn evaluate(self: *const PatternDatabase, board: Board) Cost {
  var result: Cost = 0;
  for ([_]Board{ board, board.transpose() }, self.database) |b, view| {
    var data = b.data;
    var cost: Cost = 0;

    inline for (view[b.emptyPos() >> 2]) |cost_table| {
      if (cost_table[data & 0xffff] == MAX_COST) {
        unreachable;
      }
      cost += cost_table[data & 0xffff];
      data >>= 16;
    }

    result = @max(result, cost);
  }

  return result;
}
