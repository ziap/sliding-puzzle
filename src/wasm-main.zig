const Board = @import("Board.zig");
const Pcg32 = @import("Pcg32.zig");
const Solution = @import("solver.zig").Solution;

var rng: Pcg32 = undefined;
var solution: Solution = undefined;

var buffer: [16]u8 = undefined;

fn constructBoard() Board {
  var b: u64 = 0;
  comptime var shift = 0;
  inline for (buffer) |tile| {
    b |= @as(u64, tile) << shift;
    shift += 4;
  }
  return .{ .data = b };
}

extern fn seedRng(state: *u64) void;
extern fn sendToWorker(data: u64) void;
extern fn executeSteps(steps: [*]u8, len: u32) void;

export fn bufferPtr() *const [16]u8 {
  return &buffer;
}

export fn init() void {
  seedRng(&rng.state);
}

export fn boardShuffle() *const [16]u8 {
  const board = Board.randomUniform(&rng);

  var b = board.data;
  for (&buffer) |*tile| {
    tile.* = @intCast(b & 0xf);
    b >>= 4;
  }

  return &buffer;
}

export fn boardSolvable() bool {
  return constructBoard().solvable();
}

export fn boardSolve() void {
  const board = constructBoard();
  sendToWorker(board.data);
}

export fn solutionPtr() *const Solution {
  return &solution;
}

export fn processSolution() void {
  const S = struct {
    var steps: [80]u8 = undefined;
  };
  var current = constructBoard();
  for (solution.view(), &S.steps) |board, *step| {
    const moves = current.getMoves(Board.invalid, true);
    inline for (moves.buf, 0..) |move, dir| {
      if (move.data == board.data) {
        step.* = dir;
        break;
      }
    }
    current = board;
  }

  executeSteps(&S.steps, solution.len);
}
