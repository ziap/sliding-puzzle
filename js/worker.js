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
   * @prop {() => void} init
   * @prop {(data: bigint) => void} solve
   */

  const exports = /** @type{SolverExport} */(wasm.instance.exports)
  memory = exports.memory

  exports.init()

  addEventListener("message", e => {
    exports.solve(e.data)
  })

  postMessage("ready")
})()
