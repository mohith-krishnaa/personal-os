'use client'

import { useMemo, useState } from 'react'
import type { Task } from '@/types/task'
import EditTask from './edit-task'

type View = 'DAY' | 'WEEK' | 'MONTH'

const dayKey = (d: Date) => `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`

export default function TaskCalendar({ tasks }: { tasks: Task[] }) {
  const [view, setView] = useState<View>('WEEK')
  const [cursor, setCursor] = useState(() => new Date())
  const days = useMemo(() => {
    if (view === 'DAY') return [new Date(cursor)]
    const start = new Date(cursor)
    if (view === 'WEEK') { const monday = (start.getDay() + 6) % 7; start.setDate(start.getDate() - monday) }
    else start.setDate(1)
    const count = view === 'WEEK' ? 7 : new Date(start.getFullYear(), start.getMonth()+1, 0).getDate()
    return Array.from({ length: count }, (_, i) => { const d = new Date(start); d.setDate(start.getDate()+i); return d })
  }, [cursor, view])
  const byDay = useMemo(() => tasks.reduce<Record<string, Task[]>>((a,t) => { const key = t.scheduled_start ? dayKey(new Date(t.scheduled_start)) : t.due_at ? dayKey(new Date(t.due_at)) : ''; if(key) (a[key] ??= []).push(t); return a }, {}), [tasks])
  const shift = view === 'DAY' ? 1 : view === 'WEEK' ? 7 : 30
  return <section style={{ marginTop: 18, border: '1px solid #24282f', borderRadius: 16, background: '#111419', padding: 18 }}>
    <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', gap:10, marginBottom:16 }}><div><h2 style={{margin:'0 0 4px'}}>Calendar</h2><span style={{color:'#8b949e',fontSize:13}}>Scheduled tasks and due dates</span></div><div style={{display:'flex',gap:6}}>{(['DAY','WEEK','MONTH'] as View[]).map(v=><button key={v} onClick={()=>setView(v)} style={{background:view===v?'#f4f4f5':'transparent',color:view===v?'#090a0c':'#8b949e',border:'1px solid #303640',borderRadius:8,padding:'7px 9px',fontSize:12}}>{v[0]+v.slice(1).toLowerCase()}</button>)}</div></div>
    <div style={{display:'flex',gap:8,marginBottom:14}}><button onClick={()=>setCursor(new Date())} style={{background:'transparent',color:'#f4f4f5',border:'1px solid #303640',borderRadius:8,padding:'6px 9px'}}>Today</button><button onClick={()=>setCursor(d=>new Date(d.getFullYear(),d.getMonth(),d.getDate()-shift))} style={{background:'transparent',color:'#8b949e',border:0}}>←</button><button onClick={()=>setCursor(d=>new Date(d.getFullYear(),d.getMonth(),d.getDate()+shift))} style={{background:'transparent',color:'#8b949e',border:0}}>→</button></div>
    <div style={{display:'grid',gridTemplateColumns:`repeat(${view==='DAY'?1:view==='WEEK'?7:7},minmax(0,1fr))`,gap:7}}>{days.map(d=><div key={dayKey(d)} style={{minHeight:120,border:'1px solid #24282f',borderRadius:10,padding:9,background:dayKey(d)===dayKey(new Date())?'#171b21':'#0d1014'}}><div style={{fontSize:12,color:'#8b949e',marginBottom:7}}>{d.toLocaleDateString('en-IN',{weekday:'short',day:'numeric',month:view==='MONTH'?'short':undefined})}</div>{(byDay[dayKey(d)]??[]).map(t=><div key={t.id} style={{fontSize:12,padding:'6px 7px',borderRadius:7,background:'#1b2028',marginBottom:5}}><div>{t.title}</div><div style={{color:'#8b949e',fontSize:11}}>{t.scheduled_start ? new Date(t.scheduled_start).toLocaleTimeString('en-IN',{hour:'2-digit',minute:'2-digit'}) : 'Due date'} · {t.priority}</div><EditTask task={t}/></div>)}</div>)}</div>
  </section>
}
