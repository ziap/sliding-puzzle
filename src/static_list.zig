// Static-array backed lists, they are used extensively in this project because
// everything has a strong upper bound and performance is critical
pub fn StaticList(T: type, capacity: comptime_int) type {
  return struct {
    buf: [capacity]T = undefined,

    // The type of the length of the list is dynamically computed to fit the
    // range from 0 to capacity - 1
    len: @Type(.{
      .Int = .{
        .signedness = .unsigned, 
        .bits = blk: {
          var shift: comptime_int = 0;
          var tmp: comptime_int = capacity;
          while (tmp > 0) {
            tmp >>= 1;
            shift += 1;
          }

          break :blk shift;
        },
      }
    }) = 0,

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

