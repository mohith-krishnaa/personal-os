'use client'

import { useState } from 'react'
import { createGoalAction, logProgressAction } from './actions-progress'

type Goal = { id: string; title: string; unit: string }

export function GoalForm() {
  const [open, setOpen] = useState(false)
  return <div style={{ marginBottom: 16 }}><button type="button" onClick={() => setOpen(!open)}>{open ? 'Close' : 'Add goal'}</button>{open && <form action={createGoalAction} style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 10 }}><input name="title" placeholder="Goal (e.g. Read)" required /><input name="unit" placeholder="Unit (pages)" required /><input name="target" type="number" min="1" step="any" placeholder="Target" required /><button type="submit">Create</button></form>}</div>
}

export function ProgressForm({ goal }: { goal: Goal }) {
  const [open, setOpen] = useState(false)
  return <div style={{ marginTop: 10 }}><button type="button" onClick={() => setOpen(!open)}>{open ? 'Close' : `Log ${goal.unit}`}</button>{open && <form action={logProgressAction} style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 8 }}><input type="hidden" name="goalId" value={goal.id} /><input name="value" type="number" min="0.01" step="any" placeholder={goal.unit} required /><input name="occurredOn" type="date" defaultValue={new Date().toISOString().slice(0, 10)} required /><button type="submit">Log progress</button></form>}</div>
}
