const std = @import("std");

const Iterator = std.process.Args.Iterator;

pub const DEFAULT_PDB_PATH = "patterns.bin";

pub fn getValue(
  arg: []const u8,
  iter: *Iterator,
  writer: *std.Io.Writer,
) ![]const u8 {
  return iter.next() orelse {
    try writer.print("Error: Missing value for parameter '{s}'\n", .{ arg });
    try writer.flush();
    return error.MissingParameterValue;
  };
}

fn getUint(
  T: type,
  base: u8,
  arg: []const u8,
  iter: *Iterator,
  writer: *std.Io.Writer,
) !T {
  const value = try getValue(arg, iter, writer);

  return std.fmt.parseUnsigned(T, value, base) catch |e| {
    try writer.print("Error: Invalid value '{s}' for parameter '{s}'\n", .{
      value,
      arg,
    });
    try writer.flush();
    return e;
  };
}

pub fn getU32(arg: []const u8, iter: *Iterator, writer: *std.Io.Writer) !u32 {
  return getUint(u32, 10, arg, iter, writer);
}

// Base 0 to accepts a plain decimal number as well as the prefixed forms
pub fn getSeed(arg: []const u8, iter: *Iterator, writer: *std.Io.Writer) !u64 {
  return getUint(u64, 0, arg, iter, writer);
}

pub fn reportUnknownParameter(arg: []const u8, writer: *std.Io.Writer) !void {
  try writer.print("Error: Unknown parameter '{s}'\n", .{ arg });
  try writer.flush();
}
