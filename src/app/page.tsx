const tasks = [
  { title: "Finish project architecture", time: "09:00", priority: "High", done: true },
  { title: "Study AWS certification", time: "11:00", priority: "High", done: false },
  { title: "Work on Personal OS", time: "15:00", priority: "Medium", done: false },
  { title: "Read for 30 minutes", time: "21:00", priority: "Low", done: false },
];

export default function Home() {
  const completed = tasks.filter((task) => task.done).length;
  const progress = Math.round((completed / tasks.length) * 100);

  return (
    <main style={{ maxWidth: 1180, margin: "0 auto", padding: "48px 24px" }}>
      <header style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 48 }}>
        <div>
          <div style={{ color: "#8b949e", fontSize: 14, marginBottom: 8 }}>PERSONAL OS</div>
          <h1 style={{ margin: 0, fontSize: 36 }}>Good evening.</h1>
          <p style={{ color: "#8b949e", marginTop: 10 }}>Your day, organized around what actually matters.</p>
        </div>
        <button style={{ background: "#f4f4f5", color: "#0b0d10", border: 0, borderRadius: 10, padding: "12px 18px", cursor: "pointer" }}>+ Add task</button>
      </header>

      <section style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: 20 }}>
        <div style={{ border: "1px solid #24282f", borderRadius: 16, padding: 24, background: "#111419" }}>
          <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 24 }}>
            <div>
              <h2 style={{ margin: 0 }}>Today</h2>
              <p style={{ color: "#8b949e", margin: "6px 0 0" }}>Saturday, August 29</p>
            </div>
            <span style={{ color: "#8b949e" }}>{completed}/{tasks.length} complete</span>
          </div>

          {tasks.map((task) => (
            <div key={task.title} style={{ display: "grid", gridTemplateColumns: "64px 1fr auto", gap: 16, alignItems: "center", padding: "16px 0", borderTop: "1px solid #24282f" }}>
              <span style={{ color: "#8b949e", fontSize: 13 }}>{task.time}</span>
              <div>
                <div style={{ textDecoration: task.done ? "line-through" : "none", color: task.done ? "#737b86" : "#f4f4f5" }}>{task.title}</div>
                <small style={{ color: "#8b949e" }}>{task.priority} priority</small>
              </div>
              <span style={{ fontSize: 20 }}>{task.done ? "✓" : "○"}</span>
            </div>
          ))}
        </div>

        <aside style={{ border: "1px solid #24282f", borderRadius: 16, padding: 24, background: "#111419" }}>
          <h2 style={{ marginTop: 0 }}>Daily progress</h2>
          <div style={{ fontSize: 42, fontWeight: 700, margin: "20px 0 8px" }}>{progress}%</div>
          <div style={{ height: 8, background: "#24282f", borderRadius: 99, overflow: "hidden" }}>
            <div style={{ width: `${progress}%`, height: "100%", background: "#f4f4f5" }} />
          </div>
          <p style={{ color: "#8b949e", lineHeight: 1.6 }}>Analytics will learn from your actual task history once activity tracking is connected.</p>
        </aside>
      </section>

      <section style={{ marginTop: 20, border: "1px solid #24282f", borderRadius: 16, padding: 24, background: "#111419" }}>
        <div style={{ color: "#8b949e", fontSize: 13, marginBottom: 8 }}>AI BRIEF · COMING NEXT</div>
        <h2 style={{ margin: 0 }}>Your personal agent will eventually plan from evidence.</h2>
        <p style={{ color: "#8b949e", maxWidth: 720, lineHeight: 1.6 }}>It will use your goals, calendar, task history and behavioral patterns to recommend realistic schedules instead of simply generating generic productivity advice.</p>
      </section>
    </main>
  );
}
