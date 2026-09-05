'use client'

export default function GlobalError() {
  return (
    <html lang="en">
      <body style={{ margin: 0, background: '#0d1117', color: '#f4f4f5', fontFamily: 'system-ui, sans-serif' }}>
        <main style={{ maxWidth: 640, margin: '0 auto', padding: '96px 24px' }}>
          <p style={{ color: '#8b949e', letterSpacing: '0.08em', textTransform: 'uppercase', fontSize: 12 }}>Personal OS</p>
          <h1 style={{ fontSize: 32, margin: '12px 0' }}>Something went wrong.</h1>
          <p style={{ color: '#a7b0bb', lineHeight: 1.6 }}>Reload the page and try again. Your saved data is not changed by this screen.</p>
          <a href="/" style={{ color: '#f4f4f5' }}>Return home</a>
        </main>
      </body>
    </html>
  )
}
