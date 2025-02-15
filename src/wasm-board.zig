const Board = @import("Board.zig");
const Pcg32 = @import("Pcg32.zig");

var rng: Pcg32 = undefined;

extern fn seedRng(state: *u64) void;

export var buffer: [16]u8 = undefined;

export fn init() void {
  seedRng(&rng.state);
}

export fn boardShuffle() void {
  const board = Board.randomUniform(&rng);

  var b = board.data;
  for (&buffer) |*tile| {
    tile.* = @intCast(b & 0xf);
    b >>= 4;
  }
}

fn constructBoard() Board {
  var b: u64 = 0;
  for (buffer) |tile| {
    b = (b << 4) | tile;
  }
  return .{ .data = b };
}

export fn boardSolvable() bool {
  return constructBoard().solvable();
}
