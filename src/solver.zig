const common = @import("common.zig");
const Board = @import("Board.zig");

const AStar = @import("solver/AStar.zig");
const IDAStar = @import("solver/IDAStar.zig");

const Cost = Board.Cost;

pub const MAX_SOLUTION_LEN = 80;
pub const Solution = common.StaticList(Board, MAX_SOLUTION_LEN);

pub const HybridSolver = struct {
  a_star: AStar,
  ida_star: IDAStar,

  pub fn solve(self: *HybridSolver, board: Board, heuristic: anytype) *const Solution {
    if (!board.solvable() or board.solved()) return &.{};
    if (self.a_star.trySolve(board, heuristic)) return self.a_star.reconstruct(0);

    while (true) {
      const top = self.a_star.heap[0];
      self.ida_star.init(top.f_cost - top.g_cost);

      if (self.ida_star.iterate(top.board, top.parent, heuristic)) |ida_sol| {
        var sol = self.a_star.reconstruct(0);
        @memcpy(sol.buf[sol.len.. sol.len + ida_sol.len], ida_sol.view());
        sol.len += ida_sol.len;
        return sol;
      }

      self.a_star.increaseHeuristic(0, self.ida_star.min_cost);
    }
  }
};
