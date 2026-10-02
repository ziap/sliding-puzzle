const Board = @import("../Board.zig");
const solver = @import("../solver.zig");
const common = @import("../common.zig");

const Cost = Board.Cost;
const Solution = solver.Solution;
const MAX_SOLUTION_LEN = solver.MAX_SOLUTION_LEN;

const NOT_SOLVED: Solution = .{
  .buf = undefined,
  .len = MAX_SOLUTION_LEN + 1,
};

const MAX_COST = Board.MAX_COST;

// An iterative deepening A* solver
pub fn IDAStar(Heuristic: type) type {
  return struct {
    const Self = @This();

    min_cost: Cost,
    solution: Solution,
    stack: common.StaticList(Board.MoveList, MAX_SOLUTION_LEN + 1),

    // The cost of every board in the currently evaluating path, indexed by
    // its depth
    costs: [MAX_SOLUTION_LEN + 1]Heuristic.Cost,

    pub fn init(self: *Self, h_cost: Cost) void {
      self.min_cost = h_cost;
      self.solution = NOT_SOLVED;
    }

    // Performs one iteration of IDA* and updates the minimum cost
    pub fn iterate(
      self: *Self,
      board: Board,
      parent: Board,
      cost: Heuristic.Cost,
      heuristic: Heuristic,
    ) ?*Solution {
      self.stack.len = 2;
      self.costs[0] = cost;

      // The board is always in front of the stack to avoid going backward
      // (reduces the branching factor from 4 to 3)
      self.stack.buf[0].len = 0;
      self.stack.buf[0].buf[0] = board;

      self.stack.buf[1] = board.getMoves(parent, false);

      var next_min_cost = MAX_COST;
      while (self.stack.len > 1) {
        var top = &self.stack.buf[self.stack.len - 1];

        // Popping from the array sets `arr.buf[arr.len]` to the popped
        // element, so I used that to keep track of the currently evaluating
        // path
        if (top.pop()) |next_board| {
          {
            if (next_board.solved() and (self.solution.len > self.stack.len - 1)) {
              self.solution.len = self.stack.len - 1;

              // Set the solution as the currently evaluating path, excluding
              // the original board
              for (self.solution.slice(), self.stack.view()[1..]) |*step, moves| {
                step.* = moves.buf[moves.len];
              }
            }
          }

          const depth = self.stack.len - 1;
          const prev = &self.stack.buf[depth - 1];
          const prev_board = prev.buf[prev.len];

          const next_cost = self.costs[depth - 1].update(heuristic, prev_board, next_board);
          const f_cost = depth + next_cost.get();
          if (f_cost <= self.min_cost) {
            // Append to the stack, avoid moving to the previous configuration
            self.costs[depth] = next_cost;
            self.stack.push(next_board.getMoves(prev_board, false));
          } else {
            next_min_cost = @min(next_min_cost, f_cost);
          }
        } else {
          _ = self.stack.pop() orelse unreachable;
        }
      }

      self.min_cost = next_min_cost;

      if (self.solution.len != NOT_SOLVED.len) return &self.solution;

      return null;
    }

    pub fn solve(self: *Self, board: Board, heuristic: Heuristic) *const Solution {
      if (!board.solvable() or board.solved()) return &.empty;

      const cost = heuristic.cost(board);
      self.init(cost.get());

      while (true) {
        return self.iterate(board, .invalid, cost, heuristic) orelse continue;
      }
    }
  };
}
