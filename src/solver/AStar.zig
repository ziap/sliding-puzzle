const common = @import("../common.zig");
const Board = @import("../Board.zig");
const Solution = @import("../solver.zig").Solution;

const Cost = Board.Cost;

// A dynamic-programming A* based partial solver
pub const AStar = @This();

const HEAP_BITS = 20;
const HASH_BITS = HEAP_BITS + 1; // 50% load factor

const HEAP_SIZE = 1 << HEAP_BITS;
const HASH_SIZE = 1 << HASH_BITS;

const HASH_INVALID = -% @as(HeapIndex, 1);

const HeapIndex = u32;

const HashIndex = common.Uint(HASH_BITS);

const HeapItem = struct {
  hash_idx: HashIndex,
  g_cost: Cost,
  f_cost: Cost,
  board: Board,
  parent: Board,
};

heap: [HEAP_SIZE]HeapItem,
hash_table: [HASH_SIZE]HeapIndex,
len: u32,

closed_idx: HeapIndex,

solution: Solution,

fn moveItem(self: *AStar, from: HeapIndex, to: HeapIndex) void {
  self.hash_table[self.heap[from].hash_idx] = to;
  self.heap[to] = self.heap[from];
}

fn init(self: *AStar) void {
  self.len = 0;
  self.closed_idx = HEAP_SIZE;

  @memset(&self.hash_table, HASH_INVALID);
}

fn insert(self: *AStar, board: Board, parent: Board, g_cost: Cost, heuristic: anytype) bool {
  const hash_idx, var heap_idx = blk: {
    var h = board.hash(HASH_BITS);
    var idx = self.hash_table[h];

    while (idx != HASH_INVALID) {
      if (self.heap[idx].board.data == board.data) {
        if (self.heap[idx].g_cost > g_cost) {
          // If the node is in the closed set, move it to the open set
          // This happens when our heuristic is not consistent
          // See: <https://en.wikipedia.org/wiki/Consistent_heuristic>
          if (idx >= self.closed_idx) {
            self.moveItem(self.closed_idx, idx);
            self.closed_idx += 1;

            // Add the node to the open set
            const heap_idx = self.len;
            self.len += 1;
            break :blk .{ h, heap_idx };
          }

          // The node is in the open set, but the g cost and consequentially
          // the f cost is reduced, so a sift-up is required
          break :blk .{ h, idx };
        }
        return false;
      }

      // Linear probing collision resolution
      // No mmodulo or masking required thanks to Zig's arbitrary integer
      h +%= 1;
      idx = self.hash_table[h];
    }

    // The node is not found in both the open and closed set, add it to the
    // end of the heap and perform a sift-up
    const heap_idx = self.len;
    self.len += 1;
    break :blk .{ h, heap_idx };
  };

  const h_cost = heuristic.evaluate(board);
  const f_cost = g_cost + h_cost;

  var p_idx = (heap_idx -% 1) >> 1;
  while (heap_idx > 0 and self.heap[p_idx].f_cost > f_cost) {
    self.moveItem(p_idx, heap_idx);

    heap_idx = p_idx;
    p_idx = (heap_idx -% 1) >> 1;
  }

  self.hash_table[hash_idx] = heap_idx;
  self.heap[heap_idx] = .{
    .hash_idx = hash_idx,
    .g_cost = g_cost,
    .f_cost = f_cost,
    .board = board,
    .parent = parent,
  };

  return true;
}

fn siftDown(self: *AStar, pos: HeapIndex, f_cost: Cost) HeapIndex {
  var idx = pos;
  var child_idx = (idx << 1) + 1;
  while (child_idx < self.len) {
    var child_f_cost = self.heap[child_idx].f_cost;
    if (child_idx + 1 < self.len) {
      const other = self.heap[child_idx + 1].f_cost;
      if (other < child_f_cost) {
        child_idx += 1;
        child_f_cost = other;
      }
    }

    if (f_cost < child_f_cost) break;

    self.moveItem(child_idx, idx);
    idx = child_idx;
    child_idx = (idx << 1) + 1;
  }

  return idx;
}

fn moveTopToClosed(self: *AStar) void {
  self.closed_idx -= 1;
  self.moveItem(0, self.closed_idx);

  self.len -= 1;

  if (self.len > 0) {
    const idx = self.siftDown(0, self.heap[self.len].f_cost);
    self.moveItem(self.len, idx);
  }
}

pub fn increaseHeuristic(self: *AStar, idx: HeapIndex, new_h_cost: Cost) void {
  const top = self.heap[idx];
  const f_cost = top.g_cost + new_h_cost;
  const new_idx = self.siftDown(idx, f_cost);
  self.hash_table[top.hash_idx] = new_idx;
  self.heap[new_idx] = top;
  self.heap[new_idx].f_cost = f_cost;
}

// Try to solve a puzzle configuration until either a solution is found or
// memory is exhausted
pub fn trySolve(self: *AStar, board: Board, heuristic: anytype) bool {
  self.init();

  if (!self.insert(board, Board.invalid, 0, heuristic)) unreachable;

  while (!self.heap[0].board.solved()) {
    const current = self.heap[0];

    const moves = current.board.getMoves(current.parent, false);
    const remaining = self.closed_idx - self.len;

    // This doesn't accurately determine if space is still available but it's
    // faster than trying to insert and undo when OOM
    if (remaining == 0 or remaining < moves.len) return false;

    self.moveTopToClosed();
    for (moves.view()) |neighbor| {
      _ = self.insert(neighbor, current.board, current.g_cost + 1, heuristic);
    }
  }

  return true;
}

// Reconstruct the path to a node using the generated spanning tree
pub fn reconstruct(self: *AStar, pos: HeapIndex) *Solution {
  var heap_idx = pos;
  var sol_idx = self.heap[heap_idx].g_cost;

  self.solution.len = @intCast(sol_idx);
  while (sol_idx > 0) {
    sol_idx -= 1;
    self.solution.buf[sol_idx] = self.heap[heap_idx].board;

    const p = self.heap[heap_idx].parent;

    var h = p.hash(HASH_BITS);
    heap_idx = self.hash_table[h];

    while (self.heap[heap_idx].board.data != p.data) {
      h +%= 1;
      heap_idx = self.hash_table[h];
    }
  }

  return &self.solution;
}
