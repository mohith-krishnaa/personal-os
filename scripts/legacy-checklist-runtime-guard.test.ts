import assert from 'node:assert/strict'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { extname, join, relative } from 'node:path'
import test from 'node:test'

const runtimeExtensions = new Set(['.ts', '.tsx', '.js', '.jsx'])
const testFilePattern = /\.(?:test|spec)\.(?:ts|tsx|js|jsx)$/

function collectRuntimeFiles(directory: string): string[] {
  if (!existsSync(directory)) return []

  return readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const path = join(directory, entry.name)
    if (entry.isDirectory()) return collectRuntimeFiles(path)
    if (!entry.isFile() || !runtimeExtensions.has(extname(entry.name)) || testFilePattern.test(entry.name)) return []
    return [path]
  })
}

test('application runtime uses only the canonical checklist table', () => {
  const root = process.cwd()
  const files = [
    ...collectRuntimeFiles(join(root, 'src')),
    ...collectRuntimeFiles(join(root, 'lib')),
  ]
  const middleware = join(root, 'middleware.ts')
  if (existsSync(middleware)) files.push(middleware)

  assert.ok(files.length > 0, 'Expected to inspect application runtime source files.')

  const legacyTable = ['task', 'checklist', 'items'].join('_')
  const references = files.flatMap(file =>
    readFileSync(file, 'utf8')
      .split(/\r?\n/)
      .flatMap((line, index) => line.includes(legacyTable)
        ? [`${relative(root, file)}:${index + 1}`]
        : []),
  )

  assert.deepEqual(
    references,
    [],
    `Runtime code must not call the transitional legacy checklist table:\n${references.join('\n')}`,
  )
})
