const Board = @import("../Board.zig");
const solver = @import("../solver.zig");
const StaticList = @import("../static_list.zig").StaticList;

const Cost = Board.Cost;
const Solution = solver.Solution;
const MAX_SOLUTION_LEN = solver.MAX_SOLUTION_LEN;

// An iterative deepening A* solver
const IDAStar = @This();

const NOT_SOLVED: Solution = .{ .len = MAX_SOLUTION_LEN + 1};

const MAX_COST = -% @as(Cost, 1);

min_cost: Cost,
solution: Solution,
stack: StaticList(Board.MoveList, MAX_SOLUTION_LEN + 1),

pub fn init(self: *IDAStar, h_cost: Cost) void {
  self.min_cost = h_cost;
  self.solution = NOT_SOLVED;
}

// Performs one iteration of IDA* and updates the minimum cost
pub fn iterate(self: *IDAStar, board: Board, parent: Board) ?*Solution {
  self.stack.len = 2;

  // The board is always in front of the stack to avoid going backward
  // (reduces the branching factor from 4 to 3)
  self.stack.buf[0].len = 0;
  self.stack.buf[0].buf[0] = board;

  self.stack.buf[1] = board.getMoves(parent);

  var next_min_cost = MAX_COST;
  while (self.stack.len > 1) {
    var top = &self.stack.buf[self.stack.len - 1];

    // Popping from the array sets `arr.buf[arr.len]` to the popped element,
    // so I used that to keep track of the currently evaluating path
    if (top.pop()) |next_board| {
    {
        if (next_board.solved() and (self.solution.len > self.stack.len - 1)) {
          self.solution.len = self.stack.len - 1;

          // Set the solution as the currently evaluating path, excluding the
          // original board
          for (self.solution.slice(), self.stack.view()[1..]) |*step, moves| {
            step.* = moves.buf[moves.len];
          }
        }
      }

      const f_cost = self.stack.len - 1 + next_board.heuristic();
      if (f_cost <= self.min_cost) {
        // Append to the stack, avoid moving to the previous configuration
        const prev = self.stack.buf[self.stack.len - 2];
        self.stack.push(next_board.getMoves(prev.buf[prev.len]));
      } else {
        next_min_cost = @min(next_min_cost, f_cost);
      }
    } else {
      _ = self.stack.pop() orelse unreachable;
    }
  }

  self.min_cost = next_min_cost;

  if (self.solution.len != NOT_SOLVED.len) {
    return &self.solution;
  }

  return null;
}

pub fn solve(self: *IDAStar, board: Board) *const Solution {
  if (!board.solvable() or board.solved()) {
    return &.{};
  }

  self.init(board.heuristic());

  while (true) {
    return self.iterate(board, Board.invalid) orelse continue;
  }
}
