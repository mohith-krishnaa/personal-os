import test from 'node:test'
import assert from 'node:assert/strict'
import { buildAnalyticsReview, getAnalyticsInsights, getReviewBounds } from './analytics'

test('weekly review uses Monday through Sunday UTC and compares the previous week', () => {
  const bounds = getReviewBounds('week', new Date('2026-11-27T18:00:00.000Z'))
  assert.equal(bounds.start.toISOString(), '2026-11-23T00:00:00.000Z')
  assert.equal(bounds.end.toISOString(), '2026-11-30T00:00:00.000Z')
  assert.equal(bounds.previousStart.toISOString(), '2026-11-16T00:00:00.000Z')
  assert.equal(bounds.previousEnd.toISOString(), bounds.start.toISOString())
})

test('monthly bounds handle year changes and leap February', () => {
  const bounds = getReviewBounds('month', new Date('2024-02-29T08:00:00.000Z'))
  assert.equal(bounds.start.toISOString(), '2024-02-01T00:00:00.000Z')
  assert.equal(bounds.end.toISOString(), '2024-03-01T00:00:00.000Z')
  assert.equal(bounds.previousStart.toISOString(), '2024-01-01T00:00:00.000Z')
})

test('review buckets completed tasks and progress by date and excludes period boundaries', () => {
  const bounds = getReviewBounds('week', new Date('2026-11-27T00:00:00.000Z'))
  const review = buildAnalyticsReview([
    { id: 'before', status: 'COMPLETED', completed_at: '2026-11-22T23:59:59.000Z', created_at: '2026-11-22T12:00:00.000Z', estimated_minutes: 10, actual_minutes: 12 },
    { id: 'previous', status: 'COMPLETED', completed_at: '2026-11-20T12:00:00.000Z', created_at: '2026-11-19T12:00:00.000Z', estimated_minutes: 20, actual_minutes: 25 },
    { id: 'current', status: 'COMPLETED', completed_at: '2026-11-23T09:00:00.000Z', created_at: '2026-11-23T08:00:00.000Z', estimated_minutes: 30, actual_minutes: 36 },
    { id: 'not-done', status: 'TODO', completed_at: null, created_at: '2026-11-24T12:00:00.000Z', estimated_minutes: 15, actual_minutes: null },
  ], [
    { value: 2, occurred_on: '2026-11-16' },
    { value: 3, occurred_on: '2026-11-23' },
    { value: 4, occurred_on: '2026-11-30' },
  ], bounds)

  assert.equal(review.buckets.length, 7)
  assert.equal(review.buckets[0].completed, 1)
  assert.equal(review.buckets[0].progress, 3)
  assert.equal(review.completed, 1)
  assert.equal(review.created, 2)
  assert.equal(review.plannedMinutes, 30)
  assert.equal(review.actualMinutes, 36)
  assert.equal(review.previousCompleted, 1)
  assert.equal(review.previousProgress, 2)
})

test('insights avoid estimating time accuracy without three comparable tasks', () => {
  const review = buildAnalyticsReview([
    { id: 'one', status: 'COMPLETED', completed_at: '2026-11-23T12:00:00.000Z', created_at: '2026-11-23T12:00:00.000Z', estimated_minutes: 30, actual_minutes: 40 },
  ], [], getReviewBounds('week', new Date('2026-11-27T00:00:00.000Z')))
  assert.ok(getAnalyticsInsights(review).some(value => value.includes('Record actual minutes')))
})

test('insights compare time estimates only after enough tracked tasks', () => {
  const review = buildAnalyticsReview([
    { id: 'one', status: 'COMPLETED', completed_at: '2026-11-23T12:00:00.000Z', created_at: '2026-11-23T12:00:00.000Z', estimated_minutes: 30, actual_minutes: 40 },
    { id: 'two', status: 'COMPLETED', completed_at: '2026-11-24T12:00:00.000Z', created_at: '2026-11-24T12:00:00.000Z', estimated_minutes: 30, actual_minutes: 40 },
    { id: 'three', status: 'COMPLETED', completed_at: '2026-11-25T12:00:00.000Z', created_at: '2026-11-25T12:00:00.000Z', estimated_minutes: 30, actual_minutes: 40 },
  ], [], getReviewBounds('week', new Date('2026-11-27T00:00:00.000Z')))
  assert.ok(getAnalyticsInsights(review).some(value => value.includes('33% longer')))
})

