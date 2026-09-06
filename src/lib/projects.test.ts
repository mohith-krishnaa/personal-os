import test from 'node:test'
import assert from 'node:assert/strict'
import { validateProjectName } from './project-validation'

test('organization project contract accepts valid names', () => {
  assert.equal(validateProjectName('Exam preparation'), null)
})

test('organization project contract rejects blank names', () => {
  assert.equal(validateProjectName('\t\n'), 'Project name is required')
})
