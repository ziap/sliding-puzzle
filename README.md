# Sliding puzzle solver

An algorithm to solve the 4x4 sliding-tile puzzle. It can optimally solve many
random instances of the puzzle in a fraction of a second and is small enough to
be embedded in a web page.

## Features

- Hybrid A\*/IDA\* search algorithm based on [this
paper](//www.ijcai.org/Proceedings/2019/0168.pdf).
- Optimized priority queue implementation with zero memory allocation and O(1)
time complexity for all operations.
- Additive pattern database heuristic with zero cost, compile-time
configuration.
- Compiled to WebAssembly with optimizations for both performance and loading
time for a cross-platform, responsive web UI.
- Pattern database caching with
[IndexedDB](//developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API) for
faster subsequent accesses.

## Usage

The easiest way to use the program is to go to the [deployed
website](//ziap.github.io/sliding-puzzle).

This project uses [Zig 0.16](//ziglang.org/download/#release-0.16.0). Only the
Zig compiler is required to build the project. Some additional tools that are
useful for development:

- LLDB: <https://lldb.llvm.org/>
- POOP: <https://github.com/andrewrk/poop/>
- Binaryen: <https://github.com/WebAssembly/binaryen>
- WABT: <https://github.com/WebAssembly/wabt>

### Building

```sh
zig build --release=fast
```

### Running

The CLI has two subcommands. The first writes the pattern database to disk:

```sh
sliding-puzzle generate [-o|--out <path>]
```

The second runs the algorithm on random instances of the puzzle and calculates
the maximum and average time:

```sh
sliding-puzzle evaluate [-i|--iter <u32>] [-s|--seed <u64>] [-p|--pdb <path>]
```

| Option         | Default        | Meaning                                               |
| -------------- | -------------- | ----------------------------------------------------- |
| `-o`, `--out`  | `patterns.bin` | Where to write the pattern database                   |
| `-i`, `--iter` | `1000`         | Number of puzzles to solve                            |
| `-s`, `--seed` | random         | Seed for the PRNG, decimal or `0x`/`0o`/`0b` prefixed |
| `-p`, `--pdb`  | `patterns.bin` | Where to read the pattern database from               |

If there's no pattern database at `--pdb` yet, `evaluate` generates one there
before solving, so a fresh checkout doesn't need `generate` first.

The seed is printed alongside the results, so passing it back to `--seed`
reproduces a run exactly. Pass `--help` to either subcommand for the full list
of options.

To run the web front-end, start any web server at the project's root:

```sh
# Serve the app locally with your HTTP server of choice
python3 -m http.server 8080

# Launch the app in your browser of choice
firefox http://localhost:8080
```

## License

This app is licensed under the [AGPL-3.0 license](LICENSE).
