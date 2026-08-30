'use client'

import { FormEvent, useState } from 'react'
import { createClient } from '@/lib/supabase/browser'

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [mode, setMode] = useState<'login' | 'signup'>('login')
  const [message, setMessage] = useState('')
  const [loading, setLoading] = useState(false)

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setLoading(true)
    setMessage('')

    try {
      const supabase = createClient()
      const result = mode === 'login'
        ? await supabase.auth.signInWithPassword({ email, password })
        : await supabase.auth.signUp({ email, password })

      if (result.error) setMessage(result.error.message)
      else if (mode === 'signup') setMessage('Account created. Check your email if confirmation is enabled.')
      else window.location.href = '/dashboard'
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Unable to connect to Supabase.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <main className="min-h-screen grid place-items-center p-6">
      <form onSubmit={submit} className="w-full max-w-sm space-y-5 rounded-2xl border p-7">
        <div>
          <p className="text-sm text-muted-foreground">Personal OS</p>
          <h1 className="text-2xl font-semibold">{mode === 'login' ? 'Welcome back' : 'Create your account'}</h1>
        </div>
        <input required type="email" placeholder="Email" value={email} onChange={e => setEmail(e.target.value)} className="w-full rounded-lg border px-3 py-2" />
        <input required minLength={6} type="password" placeholder="Password" value={password} onChange={e => setPassword(e.target.value)} className="w-full rounded-lg border px-3 py-2" />
        <button disabled={loading} className="w-full rounded-lg bg-black px-4 py-2 text-white disabled:opacity-50">
          {loading ? 'Working…' : mode === 'login' ? 'Sign in' : 'Create account'}
        </button>
        {message && <p className="text-sm text-muted-foreground">{message}</p>}
        <button type="button" onClick={() => setMode(mode === 'login' ? 'signup' : 'login')} className="text-sm underline">
          {mode === 'login' ? 'Create an account' : 'Already have an account? Sign in'}
        </button>
      </form>
    </main>
  )
}
