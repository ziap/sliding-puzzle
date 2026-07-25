const std = @import("std");

const Context = @This();

// Everything a subcommand is allowed to touch: the I/O implementation, a
// region to allocate its working set from, and where to write its output
io: std.Io,
arena: std.mem.Allocator,
writer: *std.Io.Writer,
