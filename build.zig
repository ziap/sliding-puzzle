const std = @import("std");

const BuildOptions = struct {
  target: std.Build.ResolvedTarget,
  optimize: std.builtin.OptimizeMode,
  strip: bool,

  fn default(b: *std.Build) BuildOptions {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    return .{
      .target = target,
      .optimize = optimize,
      .strip = optimize == .ReleaseFast or optimize == .ReleaseSmall,
    };
  }
};

fn buildCli(b: *std.Build, opt: BuildOptions) void {
  const cli = b.addExecutable(.{
    .name = "main",
    .root_source_file = b.path("src/main.zig"),
    .target = opt.target,
    .optimize = opt.optimize,
    .single_threaded = true,
    .strip = opt.strip,
  });

  b.installArtifact(cli);
  const cli_step = b.step("cli", "Build the CLI application");
  cli_step.dependOn(&cli.step);
  
  const cli_cmd = b.addRunArtifact(cli);
  if (b.args) |args| cli_cmd.addArgs(args);
  const cli_run = b.step("run-cli", "Run the CLI application");
  cli_run.dependOn(&cli_cmd.step);
}

fn generatePattern(b: *std.Build, opt: BuildOptions) void {
  const generator = b.addExecutable(.{
    .name = "pdb-gen",
    .root_source_file = b.path("src/pdb-gen.zig"),
    .target = opt.target,
    .optimize = opt.optimize,
    .single_threaded = true,
    .strip = opt.strip,
  });

  b.installArtifact(generator);
  const generate_cmd = b.addRunArtifact(generator);
  const generate = b.step("pdb-gen", "Generate the pattern database");
  generate.dependOn(&generate_cmd.step);
}

pub fn build(b: *std.Build) void {
  const opt = BuildOptions.default(b);
  generatePattern(b, opt);
  buildCli(b, opt);
}
