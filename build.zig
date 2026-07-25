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
    .name = "sliding-puzzle",
    .root_module = b.createModule(.{
      .root_source_file = b.path("src/main.zig"),
      .target = opt.target,
      .optimize = opt.optimize,
      .single_threaded = true,
      .strip = opt.strip,
    }),
  });

  b.installArtifact(cli);
  const cli_step = b.step("cli", "Build the CLI application");
  cli_step.dependOn(&cli.step);

  const cli_cmd = b.addRunArtifact(cli);
  if (b.args) |args| cli_cmd.addArgs(args);
  const cli_run = b.step("run-cli", "Run the CLI application");
  cli_run.dependOn(&cli_cmd.step);
}

fn buildWasm(b: *std.Build, opt: BuildOptions) void {
  const wasm_main = b.addExecutable(.{
    .name = "main",
    .root_module = b.createModule(.{
      .root_source_file = b.path("src/wasm-main.zig"),
      .target = opt.wasm_target,
      .optimize = opt.optimize,
      .strip = opt.strip,
    }),
  });

  wasm_main.rdynamic = true;
  wasm_main.entry = .disabled;
  const bin = wasm_main.getEmittedBin();
  const artifact = b.addInstallFile(bin, "main.wasm");

  b.getInstallStep().dependOn(&artifact.step);
}

fn buildWasmWorker(b: *std.Build, opt: BuildOptions) void {
  const wasm_worker = b.addExecutable(.{
    .name = "worker",
    .root_module = b.createModule(.{
      .root_source_file = b.path("src/wasm-worker.zig"),
      .target = opt.wasm_target,
      .optimize = opt.optimize,
      .strip = opt.strip,
    }),
  });

  wasm_worker.rdynamic = true;
  wasm_worker.entry = .disabled;
  const bin = wasm_worker.getEmittedBin();
  const artifact = b.addInstallFile(bin, "worker.wasm");

  b.getInstallStep().dependOn(&artifact.step);
}

pub fn build(b: *std.Build) void {
  const opt = BuildOptions.default(b);
  buildCli(b, opt);
  buildWasm(b, opt);
  buildWasmWorker(b, opt);
}
