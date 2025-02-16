# Sliding puzzle solver

An algorithm to solve the 4x4 sliding-tile puzzle. It can optimally solve many
random instances of the puzzle in a fraction of a second and is small enough to
be embedded in a web page.

## Usage

The easiest way to use the program is to go to the [deployed
website](//ziap.github.io/sliding-puzzle).

This project uses [Zig 0.13](//ziglang.org/download/#release-0.13.0). Only the
Zig compiler is required to build the project. Some additional tools that are
useful for development:

- LLDB: <https://lldb.llvm.org/>
- POOP: <https://github.com/andrewrk/poop/>
- Binaryen: <https://github.com/WebAssembly/binaryen>
- WABT: <https://github.com/WebAssembly/wabt>

### Building

Generate the pattern database:

```sh
zig build --release=fast pdb-gen
```

Build everything else:

```sh
zig build --release=fast
```

### Running

The following runs the algorithm on 400 random instances of the puzzle and
calculate the maximum and average time:

```sh
./zig-out/bin/main
```

To run the web front-end, start any web server at the project's root:

```sh
# Serve the app locally with your HTTP server of choice
python3 -m http.server 8080

# Launch the app in your browser of choice
firefox http://localhost:8080
```

## License

This app is licensed under the [AGPL-3.0 license](LICENSE).
