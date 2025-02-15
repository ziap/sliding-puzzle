/**
 * @param {string} msg
 * @returns {never}
 */
function assertNonNull(msg = "Non null assertion failed") {
  throw new Error(msg)
}

let manualEdit = false
let canMove = true

const statsTime = document.querySelector("#stats-time") ?? assertNonNull()
const statsLen = document.querySelector("#stats-len") ?? assertNonNull()

class Timer {
  /** @type {number} */
  startTime

  /** @type {number} */
  handler

  /**
   * @param {number} x 
   */
  step(x) {
    const elapsed = x - this.startTime
    statsTime.textContent = elapsed.toPrecision(4)

    if (!this.stopped) {
      this.handler = requestAnimationFrame(t => this.step(t))
    }
  }

  /**
   * @param {number} x 
   */
  init(x) {
    statsTime.textContent = "0"
    this.startTime = x
    this.stopped = false
    this.handler = requestAnimationFrame(t => this.step(t))
  }

  start() {
    this.handler = requestAnimationFrame(t => this.init(t))
  }

  end() {
    this.stopped = true
    cancelAnimationFrame(this.handler)
  }
}

const timer = new Timer()

class Adjacent {
  /** @type {(Element | null)[]} */
  dirs = [null, null, null, null]
}

const UP = 0
const DOWN = 1
const LEFT = 2
const RIGHT = 3

const animationClasses = [
  "slide-up", "slide-down", "slide-left", "slide-right", "appear"
]

const containers = document.querySelectorAll(".tile__container")

const neighbors = (() => {
  /** @type {Map<Element, Adjacent>} */
  const neighbors = new Map()

  for (let row = 0; row < 4; ++row) {
    for (let col = 0; col < 4; ++col) {
      const pos = row * 4 + col

      const adj = new Adjacent()

      if (row > 0) adj.dirs[UP] = containers[pos - 4]
      if (row < 3) adj.dirs[DOWN] = containers[pos + 4]
      if (col > 0) adj.dirs[LEFT] = containers[pos - 1]
      if (col < 3) adj.dirs[RIGHT] = containers[pos + 1]

      neighbors.set(containers[pos], adj)
    }
  }

  return neighbors
})()

/**
 * @param {number} dir
 */
function move(dir) {
  for (const tile of containers) {
    const child = tile.firstElementChild
    if (!child) continue

    const target = neighbors.get(tile)?.dirs[dir]

    if (target != null && target.firstElementChild == null) {
      child.classList.remove(...animationClasses)
      child.classList.add(animationClasses[dir])
      target.appendChild(child)
      break
    }
  }
}

/**
 * @param {Uint8Array} data 
 */
function setBoard(data) {
  /** @type{Element[]} */
  const children = []
  for (const tile of containers) {
    const child = tile.firstElementChild
    if (child) children.push(child)
  }

  for (let i = 0; i < 16; ++i) {
    if (data[i]) {
      const child = children.pop() ?? assertNonNull()

      child.setAttribute("data-num", data[i].toString())
      child.classList.remove(...animationClasses)
      child.classList.add("appear")
      containers[i].appendChild(child)
    }
  }
}

/**
 * @param {Uint8Array} data 
 */
function getBoard(data) {
  for (let i = 0; i < 16; ++i) {
    const tile = containers[i].firstElementChild?.getAttribute("data-num")
    data[i] = parseInt(tile ?? "0")
  }
}

{
  const keymap = new Map([
    ["w", UP], ["a", LEFT], ["s", DOWN], ["d", RIGHT],
    ["h", LEFT], ["j", DOWN], ["k", UP], ["l", RIGHT],
    ['ArrowUp', UP],
    ['ArrowDown', DOWN],
    ['ArrowLeft', LEFT],
    ['ArrowRight', RIGHT],
  ])

  document.addEventListener("keydown", e => {
    if (manualEdit || !canMove) return
    if (e.shiftKey || e.ctrlKey || e.altKey || e.metaKey) return
    const mapped = keymap.get(e.key)
    if (mapped != undefined) {
      move(mapped)
      e.preventDefault()
    }
  })
}

/** @type {WebAssembly.Memory} */
let memory

/** @type {Worker} */
let worker

const wasm = await WebAssembly.instantiateStreaming(fetch("./zig-out/main.wasm"), {
  env: {
    /**
     * @param {number} ptr 
     */
    seedRng(ptr) {
      const state = new BigUint64Array(memory.buffer, ptr, 1)
      crypto.getRandomValues(state)
    },

    /**
     * @param {bigint} data 
     */
    sendToWorker(data) {
      worker.postMessage(data)
    },

    /**
     * @param {number} ptr 
     * @param {number} len
     */
    executeSteps(ptr, len) {
      statsLen.textContent = len.toString()
      const steps = new Uint8Array(memory.buffer, ptr, len)

      let idx = 0
      function step() {
        if (idx < steps.length) {
          move(steps[idx++])
          setTimeout(step, 100)
        } else {
          canMove = true
          for (const btn of btns) btn.removeAttribute("disabled")
        }
      }
      setTimeout(step, 100)
    },
  }
})

/**
 * @typedef BoardExport
 * @prop {WebAssembly.Memory} memory
 * @prop {() => void} init
 * @prop {() => void} boardSolve
 * @prop {() => number} boardShuffle
 * @prop {() => number} bufferPtr
 * @prop {() => number} solutionPtr
 * @prop {() => boolean} boardSolvable
 * @prop {() => void} processSolution
 */

const exports = /** @type{BoardExport} */(wasm.instance.exports)

memory = exports.memory

exports.init()


/**
 * @returns {Uint8Array}
 */
function shuffle() {
  return new Uint8Array(memory.buffer, exports.boardShuffle(), 16)
}

/**
 * @returns {boolean}
 */
function solvable() {
  const board = new Uint8Array(memory.buffer, exports.bufferPtr(), 16)
  getBoard(board)
  return exports.boardSolvable()
}

/** @type{Element | null} */
let selecting = null

for (const tile of containers) {
  tile.addEventListener("click", () => {
    if (!canMove) return

    const child = tile.firstElementChild

    if (manualEdit) {
      if (selecting) {
        selecting.classList.remove("selecting")
        const selectingChild = selecting.firstElementChild ?? assertNonNull()
        selectingChild.classList.remove(...animationClasses)
        selectingChild.classList.add("appear")
        tile.appendChild(selectingChild)

        if (child) {
          child.classList.remove(...animationClasses)
          child.classList.add("appear")
          selecting.appendChild(child)
        }

        selecting = null

        if (solvable()) {
          manualBtn.removeAttribute("disabled")
        } else {
          manualBtn.setAttribute("disabled", "disabled")
        }
      } else {
        if (child == null) return
        selecting = tile
        selecting.classList.add("selecting")
      }
    } else {
      if (child == null) return
      const adj = neighbors.get(tile) ?? assertNonNull()

      for (let i = 0; i < 4; ++i) {
        const next = adj.dirs[i]
        if (next != null && next.firstElementChild == null) {
          child.classList.remove(...animationClasses)
          child.classList.add(animationClasses[i])
          next.appendChild(child)
          break
        }
      }
    }
  })
}

const defaultBoard = new Uint8Array([
  1, 2, 3, 4,
  5, 6, 7, 8,
  9, 10, 11, 12,
  13, 14, 15, 0,
])

const btns = document.querySelectorAll(".game-controls__btn")

const resetBtn = document.querySelector("#board-reset") ?? assertNonNull()
resetBtn.addEventListener("click", () => setBoard(defaultBoard))

const shuffleBtn = document.querySelector("#board-shuffle") ?? assertNonNull()
shuffleBtn.addEventListener("click", () => setBoard(shuffle()))

const manualBtn = document.querySelector("#board-manual") ?? assertNonNull()
manualBtn.addEventListener("click", () => {
  if (!manualEdit) {
    for (const btn of btns) btn.setAttribute("disabled", "disabled")
    manualBtn.removeAttribute("disabled")
    manualBtn.textContent = "Done"
    manualEdit = true
  } else {
    for (const btn of btns) btn.removeAttribute("disabled")
    manualBtn.textContent = "Manual"
    manualEdit = false
  }
})

worker = new Worker("./js/worker.js")

await new Promise(resolve => {
  worker.addEventListener("message", e => {
    const msg = e.data
    if (msg != "ready") throw new Error(`Expected 'ready', got ${msg}`)
    resolve(worker)
  }, { once: true })
})

const solveBtn = document.querySelector("#board-solve") ?? assertNonNull()
solveBtn.textContent = "Solve"
solveBtn.addEventListener("click", () => {
  for (const btn of btns) btn.setAttribute("disabled", "disabled")
  canMove = false
  const board = new Uint8Array(memory.buffer, exports.bufferPtr(), 16)
  getBoard(board)
  exports.boardSolve()

  timer.start()
})

worker.addEventListener("message", e => {
  timer.end()
  const solution = new Uint8Array(memory.buffer, exports.solutionPtr(), e.data.length)
  solution.set(e.data)
  exports.processSolution()
})

export {}
