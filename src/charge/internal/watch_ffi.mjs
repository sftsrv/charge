import fs from 'node:fs'
import path from 'node:path';

/**
 * @param {string} p
 */
function abs(p) {
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
      const isIgnored = ignores.some(d => path.startsWith(d))

      if (isIgnored) {
        return true
      }

      if (file.endsWith(".bck")) {
        return true
      }

      return false
    }
  }, (_ev, file) => {
    if (!file) return

    if (running) {
      console.log("currently running, update queued")
      queued = true
      return
    }

    running = true
    setTimeout(async () => {
      if (queued) {
        console.log("re-running")
        queued = false

        lastResult = await f(file)

        running = false
      }
    }, 1000)

  })


  return new Promise((res, rej) => {
    watcher.addListener('close', () => res(lastResult))
    watcher.addListener('error', (err) => rej(err))
  })
}
