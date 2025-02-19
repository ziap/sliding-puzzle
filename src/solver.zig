const common = @import("common.zig");
const Board = @import("Board.zig");

const AStar = @import("solver/AStar.zig");
const IDAStar = @import("solver/IDAStar.zig");

const Cost = Board.Cost;

pub const MAX_SOLUTION_LEN = 80;
pub const Solution = common.StaticList(Board, MAX_SOLUTION_LEN);

// A combination of A* and IDA* that combines the speed and low memory overhead
// of IDA* and duplicate node detection of A*.
// Paper: <https://www.ijcai.org/Proceedings/2019/0168.pdf>
pub const HybridSolver = struct {
  a_star: AStar,
  ida_star: IDAStar,

  pub fn solve(self: *HybridSolver, board: Board, heuristic: anytype) *const Solution {
    if (!board.solvable() or board.solved()) return &.{};
    if (self.a_star.trySolve(board, heuristic)) |pos| {
      return self.a_star.reconstruct(pos);
    }

    while (true) {
      for (self.a_star.frontier.view()) |node_idx| {
        const node = &self.a_star.nodes[node_idx];
        const current = self.a_star.boards[node_idx];
        const parent = self.a_star.boards[node.parent];

        self.ida_star.init(node.h_cost);
        if (self.ida_star.iterate(current, parent, heuristic)) |ida_sol| {
          var sol = self.a_star.reconstruct(node_idx);
          @memcpy(sol.buf[sol.len.. sol.len + ida_sol.len], ida_sol.view());
          sol.len += ida_sol.len;
          return sol;
        }

        node.h_cost += 2;
        if (self.ida_star.min_cost != node.h_cost) unreachable;
        self.a_star.next_frontier.push(node_idx);
      }

      self.a_star.swap();
    }
  }
};
