pub fn Uint(BITS: comptime_int) type {
  return @Int(.unsigned, BITS);
}

pub fn UintFit(MAX: comptime_int) type {
  var shift: comptime_int = 0;
  while (1 << shift < MAX) shift += 1;

  return Uint(shift);
}

// Fixed-array backed lists, they are used extensively in this project because
// everything has a strong upper bound and performance is critical
fn FixedBufferList(T: type, BufferType: type, LengthType: type) type {
  return struct {
    buf: BufferType,
    len: LengthType,

    pub const empty: @This() = .{
      .buf = undefined,
      .len = 0,
    };

    pub fn view(self: *const @This()) []const T {
      return self.buf[0..self.len];
    }

    pub fn slice(self: *@This()) []T {
      return self.buf[0..self.len];
    }

    // Adds an element to the end of the list, doesn't check for overflow
    // because they are caught in debug build anyways
    pub fn push(self: *@This(), item: T) void {
      self.buf[self.len] = item;
      self.len += 1;
    }

    // Remove and returns the last element from the list
    // Can be used to drain and iterate the array backward
    pub fn pop(self: *@This()) ?T {
      if (self.len == 0) return null;

      const item = self.buf[self.len - 1];
      self.len = self.len - 1;

      return item;
    }
  };
}

// Static-array backed owning lists
pub fn StaticList(T: type, capacity: comptime_int) type {
  return FixedBufferList(T, [capacity]T, UintFit(capacity + 1));
}

fn SliceList(T: type) type {
  return FixedBufferList(T, []T, usize);
}

// Slice backed lists for more flexibility but non-owning
pub fn sliceList(T: type, buf: []T) SliceList(T) {
  return .{
    .buf = buf,
    .len = 0,
  };
}
