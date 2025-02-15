const std = @import("std");

const BuildOptions = struct {
  target: std.Build.ResolvedTarget,
  wasm_target: std.Build.ResolvedTarget,
  optimize: std.builtin.OptimizeMode,
  strip: bool,

  fn default(b: *std.Build) BuildOptions {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wasm_target = b.resolveTargetQuery(.{
      .cpu_arch = .wasm32,
      .os_tag = .freestanding,
      .cpu_features_add = std.Target.wasm.featureSet(&.{
        .atomics,
        .bulk_memory,
        .extended_const,
        .multivalue,
        .mutable_globals,
        .nontrapping_fptoint,
        .sign_ext,
        .simd128,
        .tail_call,
      }),
    });
    return .{
      .target = target,
      .optimize = optimize,
      .wasm_target = wasm_target,
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

  const generate_cmd = b.addRunArtifact(generator);
  const generate = b.step("pdb-gen", "Generate the pattern database");
  generate.dependOn(&generate_cmd.step);
}

fn buildWasmBoard(b: *std.Build, opt: BuildOptions) void {
  const wasm_board = b.addExecutable(.{
    .name = "board",
    .root_source_file = b.path("src/wasm-board.zig"),
    .target = opt.wasm_target,
    .optimize = opt.optimize,
    .strip = opt.strip,
  });

  wasm_board.rdynamic = true;
  wasm_board.entry = .disabled;
  const bin = wasm_board.getEmittedBin();
  const artifact = b.addInstallFile(bin, "board.wasm");

  b.getInstallStep().dependOn(&artifact.step);
}

pub fn build(b: *std.Build) void {
  const opt = BuildOptions.default(b);
  generatePattern(b, opt);
  buildCli(b, opt);
  buildWasmBoard(b, opt);
}
