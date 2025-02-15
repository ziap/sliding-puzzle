const Board = @import("Board.zig");
const solver = @import("solver.zig");
const Heuristic = @import("pattern-database.zig").Default;

const Cost = Board.Cost;

const Memory = union {
  solver: solver.HybridSolver,
  buffer: Heuristic.ScratchBuffer,
};

const heuristic = blk: {
  const S = struct {
    var heuristic: Heuristic = undefined;
  };

  break :blk &S.heuristic;
};

const memory = blk: {
  const S = struct {
    var memory: Memory = undefined;
  };

  break :blk &S.memory;
};

extern fn doneSearch(solution: *const solver.Solution, size: u32) void;

export fn init() void {
  heuristic.generate(&memory.buffer);
}

export fn solve(data: u64) void {
  const solution = memory.solver.solve(.{ .data = data }, heuristic);
  doneSearch(solution, @sizeOf(solver.Solution));
}
