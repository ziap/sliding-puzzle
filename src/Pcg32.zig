const Pcg32 = @This();

// Fixed-increment version of PCG-32-XSH-RR
// Copied and modified from: https://www.pcg-random.org/download.html
state: u64,

const MUL = 0x5851f42d4c957f2d;
const INC = 0x14057b7ef767814f;

// Create and seed an RNG with a non-random seed
pub fn withSeed(seed: u64) Pcg32 {
  return .{ .state = (INC + seed) *% MUL +% INC };
}

pub fn next(self: *Pcg32) u32 {
  const state = self.state;
  self.state = state *% MUL +% INC;

  const xorshifted: u32 = @truncate((state ^ (state >> 18)) >> 27);
  const rot: u5 = @intCast(state >> 59);
  return (xorshifted >> rot) | (xorshifted << -% rot);
}

// Unbiased random integer generation in a range, Lemire's method
// Paper: https://arxiv.org/pdf/1805.10941.pdf
pub fn bounded(self: *Pcg32, range: u32) u32 {
  const t = (-% range) % range;

  while (true) {
    const x = self.next();
    const m = @as(u64, x) * @as(u64, range);
    const l: u32 = @truncate(m);

    if (l >= t) {
      return @intCast(m >> 32);
    }
  }
}
