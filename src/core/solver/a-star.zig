const common = @import("../common.zig");
const Board = @import("../Board.zig");
const Solution = @import("../solver.zig").Solution;

const Cost = Board.Cost;

const HASH_BITS = 20;
const HASH_SIZE = 1 << HASH_BITS;

const STACK_SIZE = HASH_SIZE / 2; // 50% load factor

const StackIndex = u32;
const HashIndex = common.Uint(HASH_BITS);

const HASH_INVALID: StackIndex = @truncate(-1);

const Stack = common.StaticList(StackIndex, STACK_SIZE);

// A dynamic-programming A* based partial solver
pub fn AStar(Heuristic: type) type {
  return struct {
    const Self = @This();

    const Node = struct {
      g_cost: Cost,
      cost: Heuristic.Cost,

      // The cost bound of the IDA* search continuing from this node, starts
      // as the node's heuristic cost
      bound: Cost,
      parent: u32,
    };

    stacks: [2]Stack,

    hash_table: [HASH_SIZE]StackIndex,
    nodes: [STACK_SIZE]Node,
    boards: [STACK_SIZE]Board,
    len: StackIndex,

    frontier: *Stack,
    next_frontier: *Stack,
    solution: Solution,

    fn init(self: *Self) void {
      self.len = 0;

      self.frontier = &self.stacks[0];
      self.next_frontier = &self.stacks[1];

      self.frontier.len = 0;
      self.next_frontier.len = 0;

      @memset(&self.hash_table, HASH_INVALID);
    }

    fn get(self: *Self, board: Board) *StackIndex {
      var h = board.hash(HASH_BITS);
      var idx = &self.hash_table[h];

      while (idx.* != HASH_INVALID) {
        if (self.boards[idx.*].data == board.data) {
          return idx;
        }

        h +%= 1;
        idx = &self.hash_table[h];
      }

      return idx;
    }

    pub fn swap(self: *Self) void {
      const tmp = self.frontier;
      self.frontier = self.next_frontier;
      self.next_frontier = tmp;
      self.next_frontier.len = 0;
    }

    pub fn trySolve(self: *Self, board: Board, heuristic: Heuristic) ?StackIndex {
      self.init();

      const cost = heuristic.cost(board);
      var f_cost = cost.get();

      self.get(board).* = 0;
      self.nodes[0] = .{
        .g_cost = 0,
        .cost = cost,
        .bound = f_cost,
        .parent = 0,
      };
      self.boards[0] = board;
      self.len = 1;

      self.frontier.push(0);

      while (true) {
        while (self.frontier.pop()) |node_idx| {
          const node = self.nodes[node_idx];

          if (self.boards[node_idx].solved()) return node_idx;
          if (node.g_cost + node.cost.get() != f_cost) continue;

          if (self.len + 3 >= STACK_SIZE) {
            self.frontier.push(node_idx);
            var idx: @TypeOf(self.next_frontier.len) = 0;
            for (self.next_frontier.view()) |next_node_idx| {
              const next_node = self.nodes[next_node_idx];
              if (next_node.g_cost + next_node.cost.get() == f_cost + 2) {
                self.next_frontier.buf[idx] = next_node_idx;
                idx += 1;
              }
            }

            self.next_frontier.len = idx;
            return null;
          }

          const current = self.boards[node_idx];
          const moves = current.getMoves(self.boards[node.parent], false);
          for (moves.view()) |next| {
            const idx = self.get(next);
            if (idx.* == HASH_INVALID) {
              idx.* = self.len;
              self.len += 1;
              const g_cost = node.g_cost + 1;
              const next_cost = node.cost.update(heuristic, current, next);
              const h_cost = next_cost.get();
              self.nodes[idx.*] = .{
                .g_cost = g_cost,
                .cost = next_cost,
                .bound = h_cost,
                .parent = node_idx,
              };
              self.boards[idx.*] = next;

              if (g_cost + h_cost == f_cost) {
                self.frontier.push(idx.*);
              } else {
                if (g_cost + h_cost != f_cost + 2) unreachable;
                self.next_frontier.push(idx.*);
              }
            } else {
              const next_node = &self.nodes[idx.*];
              if (next_node.g_cost > node.g_cost + 1) {
                next_node.g_cost = node.g_cost + 1;
                next_node.parent = node_idx;
                self.frontier.push(idx.*);
              }
            }
          }
        }

        self.swap();
        f_cost += 2;
      }
    }

    pub fn reconstruct(self: *Self, pos: StackIndex) *Solution {
      var idx = pos;
      var sol_idx = self.nodes[idx].g_cost;

      self.solution.len = @intCast(sol_idx);
      while (sol_idx > 0) {
        sol_idx -= 1;

        self.solution.buf[sol_idx] = self.boards[idx];
        idx = self.nodes[idx].parent;
      }

      return &self.solution;
    }
  };
}
