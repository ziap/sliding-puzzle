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

  const openRequest = indexedDB.open("pdb-store", 1)

  const storeName = "object-store"
  const patternId = "id"

  openRequest.addEventListener("upgradeneeded", () => {
    const db = openRequest.result
    if (!db.objectStoreNames.contains(storeName)) {
      db.createObjectStore(storeName)
    }
  })

  openRequest.addEventListener("success", () => {
    const db = openRequest.result
    const read = db.transaction(storeName, "readonly")
    const readStore = read.objectStore(storeName)

    const request = readStore.get(patternId)
    const database = new Uint8Array(memory.buffer, exports.databasePtr(), exports.databaseSize())

    request.addEventListener("success", async e => {
      const result = /**@type{IDBRequest<ArrayBuffer>}*/(e.target).result

      if (result) {
        database.set(new Uint8Array(result))
      } else {
        const resp = await fetch("../patterns.gz")
        const stream = resp.body?.pipeThrough(new DecompressionStream("deflate-raw"))
        const buffer = await new Response(stream).arrayBuffer()

        const write = db.transaction(storeName, "readwrite")
        const writeStore = write.objectStore(storeName)
        writeStore.add(buffer, patternId)

        const database = new Uint8Array(memory.buffer, exports.databasePtr(), exports.databaseSize())
        database.set(new Uint8Array(buffer))
      }
      postMessage("ready")
    })
  })

  addEventListener("message", e => exports.solve(e.data))
})()
