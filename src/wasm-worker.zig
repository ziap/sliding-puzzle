const Board = @import("Board.zig");
const Heuristic = @import("pattern-database.zig").Default;

const solver = @import("solver.zig");
const Solver = solver.HybridSolver;
const Solution = solver.Solution;

const Cost = Board.Cost;

const ctx = blk: {
  const S = struct {
    var solver: Solver = undefined;
    var heuristic: Heuristic = undefined;
  };

  break :blk .{
    .solver = &S.solver,
    .heuristic = &S.heuristic
  };
};

extern fn doneSearch(solution: *const Solution, size: u32) void;

export fn databasePtr() *Heuristic.Database {
  return &ctx.heuristic.database;
}

export fn databaseSize() u32 {
  return @sizeOf(Heuristic.Database);
}

export fn solve(data: u64) void {
  const solution = ctx.solver.solve(.{ .data = data }, ctx.heuristic);
  doneSearch(solution, @sizeOf(Solution));
}
