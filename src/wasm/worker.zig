const core = @import("core");

const Board = core.Board;
const Solver = core.HybridSolver;
const Solution = core.Solution;

const Heuristic = core.PatternDatabase;

const Cost = Board.Cost;

const ctx = blk: {
  const S = struct {
    var solver: Solver = undefined;
    var database: Heuristic.Database = undefined;
  };

  break :blk .{
    .solver = &S.solver,
    .database = &S.database,
  };
};

extern fn doneSearch(solution: *const Solution, size: u32) void;

export fn databasePtr() *Heuristic.Database {
  return ctx.database;
}

export fn databaseSize() u32 {
  return @sizeOf(Heuristic.Database);
}

export fn solve(data: u64) void {
  const heuristic: Heuristic = .{ .database = ctx.database };
  const solution = ctx.solver.solve(.{ .data = data }, heuristic);
  doneSearch(solution, @sizeOf(Solution));
}
