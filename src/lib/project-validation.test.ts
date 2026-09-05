import test from 'node:test'
import assert from 'node:assert/strict'
import { validateProjectName } from './project-validation'

test('rejects empty project names', () => {
  assert.equal(validateProjectName('   '), 'Project name is required')
})

test('accepts a trimmed valid project name', () => {
  assert.equal(validateProjectName('  Personal OS  '), null)
})

test('rejects project names over 120 characters', () => {
  assert.equal(validateProjectName('a'.repeat(121)), 'Project name must be 120 characters or fewer')
})
