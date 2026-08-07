import fs from 'node:fs'
import path from 'node:path';

/**
 * @param {string} p
 */
function abs(p){
  return path.join(process.cwd(), p)
}

/**
 * @param {(path: string)=> Promise<unknown>} f
 * @param {string} root
 * @param {string[]} ignores
 */
export function watch(root, ignores, f) {
  let queued = true
  let running = false

  /**
   * @type {unknown}
   */
  let lastResult;

  const watcher = fs.watch(root, {
    recursive: true,
    ignore: (file) => {
      const path = abs(file)
      console.log(path, ignores)
      return ignores.some(d => path.startsWith(d))
    }
  }, async (_ev, file) => {
    if (!file) return

    if (running) {
      console.log("currently running, update queued")
      queued = true
      return
    }

    if (queued) {
      console.log("starting new run")
      queued = false
      running = true
      lastResult = await f(file)
      running = false
    }
  })


  return new Promise((res, rej) => {
    watcher.addListener('close', () => res(lastResult))
    watcher.addListener('error', (err) => rej(err))
  })
}
