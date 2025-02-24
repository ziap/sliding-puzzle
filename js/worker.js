/// <reference lib="webworker" />

;(async () => {
  /** @type{WebAssembly.Memory} */
  var memory
  const wasm = await WebAssembly.instantiateStreaming(fetch("../zig-out/worker.wasm"), {
    env: {
      /**
       * @param {number} ptr 
       * @param {number} len 
       */
      doneSearch(ptr, len) {
        const solution = new Uint8Array(
          memory.buffer,
          ptr,
          len,
        ).slice()
        postMessage(solution, [solution.buffer])
      }
    }
  })

  /**
   * @typedef SolverExport
   * @prop {WebAssembly.Memory} memory
   * @prop {() => number} databasePtr
   * @prop {() => number} databaseSize
   * @prop {(data: bigint) => void} solve
   */

  const exports = /** @type{SolverExport} */(wasm.instance.exports)
  memory = exports.memory

  addEventListener("message", e => exports.solve(e.data))

  const resp = await fetch("../patterns.gz")
  const stream = resp.body?.pipeThrough(new DecompressionStream("deflate-raw"))
  const buffer = await new Response(stream).arrayBuffer()

  const database = new Uint8Array(memory.buffer, exports.databasePtr(), exports.databaseSize())
  database.set(new Uint8Array(buffer))

  postMessage("ready")
})()
