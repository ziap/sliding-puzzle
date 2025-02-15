/** @type {WebAssembly.Memory} */
var memory

const wasm = await WebAssembly.instantiateStreaming(fetch("./zig-out/board.wasm"), {
  env: {
    /**
     * @param {number} ptr 
     */
    seedRng(ptr) {
      const state = new BigUint64Array(memory.buffer, ptr, 1)
      crypto.getRandomValues(state)
    }
  }
})

/**
 * @typedef BoardExport
 * @prop {WebAssembly.Memory} memory
 * @prop {WebAssembly.Global} buffer
 * @prop {() => void} init
 * @prop {() => number} boardShuffle
 * @prop {() => boolean} boardSolvable
 */

const exports = /** @type{BoardExport} */(wasm.instance.exports)
const buffer = exports.buffer

memory = exports.memory

exports.init()

/**
 * @returns {Uint8Array}
 */
export function shuffle() {
  exports.boardShuffle()
  return new Uint8Array(memory.buffer, buffer.value, 16)
}

/**
 * @param {(data: Uint8Array) => void} data
 * @returns {boolean}
 */
export function solvable(data) {
  const board = new Uint8Array(memory.buffer, buffer.value, 16)
  data(board)
  return exports.boardSolvable()
}
