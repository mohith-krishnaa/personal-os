import test from 'node:test'
import assert from 'node:assert/strict'
import { validateProjectName } from './project-validation'

test('organization project contract accepts valid names', () => {
  assert.equal(validateProjectName('Exam preparation'), null)
})

test('organization project contract accepts names at the 120-character limit', () => {
  assert.equal(validateProjectName('P'.repeat(120)), null)
})

test('organization project contract rejects blank names', () => {
  assert.equal(validateProjectName('\t\n'), 'Project name is required')
})

test('organization project contract rejects names over 120 characters', () => {
  assert.equal(validateProjectName('P'.repeat(121)), 'Project name must be 120 characters or fewer')
})
