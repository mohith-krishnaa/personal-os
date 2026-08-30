import type { Reminder } from '@/types/reminder'

function formatDate(value: string) {
  return new Intl.DateTimeFormat('en-IN', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
}

export default function ReminderList({ reminders }: { reminders: Reminder[] }) {
  return reminders.length ? <div style={{ display: 'grid', gap: 8 }}>{reminders.map(reminder => <div key={reminder.id} style={{ padding: 10, border: '1px solid #24282f', borderRadius: 10 }}><div>{formatDate(reminder.remind_at)}</div><small style={{ color: '#8b949e' }}>{reminder.timezone} · {reminder.channel}</small></div>)}</div> : <p style={{ color: '#8b949e' }}>No upcoming reminders.</p>
}
