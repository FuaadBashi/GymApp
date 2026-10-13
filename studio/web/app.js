// GymApp Studio interface. Plain JavaScript: one router, one fetch helper, one renderer per page.
const $ = (sel, el = document) => el.querySelector(sel);
const main = $("#main");
const VOLT = "#c7f242", DIM = "#9a9aa3", LINE = "#2e2e33", ORANGE = "#ff9f5a", BLUE = "#73a9ff";
const charts = [];

async function api(path, options) {
  const r = await fetch("/api/" + path, options);
  const body = await r.json();
  if (!r.ok) throw new Error(body.error || r.statusText);
  return body;
}
const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const fmt = (n, d = 0) => n == null ? "–" : Number(n).toLocaleString(undefined, { maximumFractionDigits: d, minimumFractionDigits: 0 });
const day = iso => new Date(iso).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" });
const dayShort = iso => new Date(iso).toLocaleDateString(undefined, { day: "numeric", month: "short" });
const muscleName = m => ({ middleBack: "Middle back", lowerBack: "Lower back" }[m] || m.charAt(0).toUpperCase() + m.slice(1));
const statusChip = s => `<span class="chip ${s.replace(/ /g, "-")}">${esc(s)}</span>`;

function chart(el, option) {
  const c = echarts.init(el, null, { renderer: "canvas" });
  c.setOption(Object.assign({
    backgroundColor: "transparent", textStyle: { color: DIM, fontFamily: "-apple-system, system-ui" },
    grid: { left: 44, right: 16, top: 24, bottom: 30 },
    tooltip: { trigger: "axis", backgroundColor: "#1c1c1f", borderColor: LINE, textStyle: { color: "#f2f2f4" } },
  }, option));
  charts.push(c);
  return c;
}
window.addEventListener("resize", () => charts.forEach(c => c.resize()));
const axis = extra => Object.assign({ axisLine: { lineStyle: { color: LINE } }, splitLine: { lineStyle: { color: "#ffffff0d" } }, axisLabel: { color: DIM } }, extra);

// Router

const pages = {};
async function route() {
  charts.splice(0).forEach(c => c.dispose());
  closeDrawer();
  const [page, ...rest] = (location.hash.slice(2) || "overview").split("/");
  document.querySelectorAll("nav a").forEach(a => a.classList.toggle("active", a.dataset.page === page));
  main.innerHTML = `<div class="empty">Loading…</div>`;
  try {
    await (pages[page] || pages.overview)(decodeURIComponent(rest.join("/")));
  } catch (e) {
    main.innerHTML = `<h1>Can't load this yet</h1><p class="sub">${esc(e.message)}</p>`;
  }
}
window.addEventListener("hashchange", route);

async function refreshStatus() {
  const s = await api("status");
  $("#backup").innerHTML = s.backup
    ? `<b class="volt">●</b> ${s.workouts} workouts<br>${esc(s.backup.split("/").pop())}<br>loaded ${new Date(s.loaded_at).toLocaleTimeString()}`
    : `<b class="orange">●</b> No backup found. Put the phone's backup folder in iCloud Drive, or copy a backup into data/backups.`;
}

// Overview

pages.overview = async () => {
  const o = await api("overview");
  const b = o.balance;
  main.innerHTML = `
    <h1>Overview</h1>
    <p class="sub">${fmt(o.totals.workouts)} workouts and ${fmt(o.totals.sets)} sets since ${day(o.totals.since)}.</p>
    <div class="grid g4">
      <div class="card tile"><div class="k">This week</div><div class="v">${o.this_week.workouts}</div><div class="c">${fmt(o.this_week.volume_kg)} kg volume</div></div>
      <div class="card tile"><div class="k">Streak</div><div class="v">${o.consistency.current_streak_weeks} wk</div><div class="c">${o.consistency.average_per_week} sessions / week, last 26 weeks</div></div>
      <div class="card tile"><div class="k">Plateaus</div><div class="v ${o.plateaus.length ? "orange" : ""}">${o.plateaus.length}</div><div class="c">3 weeks without a weight increase</div></div>
      <div class="card tile"><div class="k">Last workout</div><div class="v" style="font-size:20px">${esc(o.last_workout?.title || "–")}</div><div class="c">${o.last_workout ? day(o.last_workout.date) + " · " + fmt(o.last_workout.volume_kg) + " kg" : ""}</div></div>
    </div>
    <h2 style="margin-top:26px">Next session · double progression</h2>
    <div class="grid g4" id="targets"></div>
    <div class="grid g3" style="margin-top:16px">
      <div class="card span2"><h2>Sessions per week</h2><div class="chart" id="weeks"></div></div>
      <div class="card"><h2>Balance · last 4 weeks</h2><div class="chart" id="balance"></div></div>
    </div>
    <div class="grid g2" style="margin-top:16px">
      <div class="card"><h2>Plateaus</h2>${o.plateaus.length ? `<div class="list">${o.plateaus.map(p => `
        <a class="row" href="#/exercises/${encodeURIComponent(p.id)}"><div class="grow"><div class="t">${esc(p.name)}</div><div class="s">${p.sessions} sessions · last ${day(p.last_done)}</div></div>${statusChip("plateau")}</a>`).join("")}</div>`
        : `<div class="empty">No plateaus: every lift you trained in the last 3 weeks went up, or is rebuilding after a break.</div>`}</div>
      <div class="card"><h2>Breaks</h2><table><tr><th>From</th><th>Days</th></tr>${o.breaks.map(x => `<tr><td>${day(x.from)}</td><td>${x.days}</td></tr>`).join("")}</table></div>
    </div>`;
  $("#targets").innerHTML = o.next_targets.map(t => `
    <a class="card target" href="#/exercises/${encodeURIComponent(t.id)}">
      <div style="display:flex;justify-content:space-between;gap:8px"><span class="muted" style="font-size:13px">${esc(t.name)}</span>${statusChip(t.kind)}</div>
      <div class="w">${fmt(t.weight, 2)} ${t.unit} <span class="muted" style="font-size:15px">× ${esc(t.reps)}</span></div>
      <div class="why">${esc(t.reason)}</div>
      <div class="last">Last: ${t.last.map(esc).join(" · ")}</div>
    </a>`).join("") || `<div class="empty">No active program in the backup.</div>`;
  chart($("#weeks"), {
    xAxis: axis({ type: "category", data: o.consistency.weeks.map(dayShort) }),
    yAxis: axis({ type: "value", minInterval: 1 }),
    series: [{ type: "bar", data: o.consistency.sessions, itemStyle: { color: VOLT, borderRadius: [4, 4, 0, 0] } }],
  });
  const ratios = [["Push : pull", b.push_pull.ratio], ["Upper : lower", b.upper_lower.ratio], ["Quads : hams", b.quads_hamstrings.ratio], ["Chest : back", b.chest_back.ratio]];
  chart($("#balance"), {
    grid: { left: 96, right: 30, top: 10, bottom: 24 },
    xAxis: axis({ type: "log", min: 0.25, max: 4, axisLabel: { color: DIM, formatter: v => v + "×" } }),
    yAxis: axis({ type: "category", data: ratios.map(r => r[0]), inverse: true }),
    tooltip: { trigger: "item", formatter: p => `${p.name}: ${p.value}×` },
    series: [{ type: "bar", data: ratios.map(r => ({ value: r[1] ?? 0.25, itemStyle: { color: r[1] == null ? LINE : (r[1] > 1.5 || r[1] < 0.67 ? ORANGE : VOLT), borderRadius: 4 } })),
      markLine: { symbol: "none", data: [{ xAxis: 1 }], lineStyle: { color: DIM, type: "dashed" }, label: { show: false } } }],
  });
};

// Exercises

let exerciseIndex = null;
pages.exercises = async (id) => {
  exerciseIndex = exerciseIndex || await api("exercises");
  main.innerHTML = `
    <div class="split">
      <div class="card side">
        <input type="search" id="q" placeholder="Search ${exerciseIndex.length} exercises" autofocus>
        <div style="margin:10px 0" class="seg" id="filter"><button data-f="all" class="on">All</button><button data-f="program">Program</button><button data-f="plateau">Plateaus</button></div>
        <div class="list" id="exlist"></div>
      </div>
      <div id="detail"><div class="empty">Choose an exercise.</div></div>
    </div>`;
  let filter = "all";
  const draw = () => {
    const q = $("#q").value.toLowerCase();
    $("#exlist").innerHTML = exerciseIndex.filter(e => e.name.toLowerCase().includes(q)
      && (filter === "all" || (filter === "program" && e.in_program) || (filter === "plateau" && e.plateau === "plateau")))
      .map(e => `<a class="row ${e.id === id ? "active" : ""}" href="#/exercises/${encodeURIComponent(e.id)}">
        <div class="grow"><div class="t">${esc(e.name)}</div><div class="s">${e.sessions} sessions · ${dayShort(e.last_done)}${e.best_e1rm ? " · e1RM " + fmt(e.best_e1rm, 1) : ""}</div></div>
        ${e.plateau === "plateau" || e.plateau === "progressing" ? statusChip(e.plateau) : ""}</a>`).join("");
  };
  $("#q").addEventListener("input", draw);
  $("#filter").addEventListener("click", ev => {
    if (!ev.target.dataset.f) return;
    filter = ev.target.dataset.f;
    [...$("#filter").children].forEach(b => b.classList.toggle("on", b === ev.target));
    draw();
  });
  draw();
  if (id) await exerciseDetail(id);
};

async function exerciseDetail(id) {
  const d = await api("exercise/" + encodeURIComponent(id));
  const r = d.records, p = d.plateau, pr = d.progress, n = d.next, inc = d.increment, f = d.formulas;
  const mark = (label, m, unit = "kg") => m ? `<tr class="click" data-w="${m.workout_id}"><td>${label}</td><td>${fmt(m.kg, 2)} ${unit}${m.reps ? " × " + m.reps : ""}</td><td class="muted">${day(m.date)}</td></tr>` : "";
  $("#detail").innerHTML = `
    <h1>${esc(d.name)}</h1>
    <p class="sub">${esc(d.equipment)} · ${esc(d.load_mode)} · ${d.muscles.primary.map(muscleName).join(", ")}${d.muscles.secondary.length ? ` <span class="faint">+ ${d.muscles.secondary.map(muscleName).join(", ")}</span>` : ""}</p>
    <div class="grid g3">
      <div class="card target">${n ? `<h2>Next session</h2><div class="w">${fmt(n.weight, 2)} ${n.unit} <span class="muted" style="font-size:15px">× ${esc(n.reps)}</span></div>${statusChip(n.kind)}<div class="why">${esc(n.reason)}</div><div class="last">Last: ${n.last.map(esc).join(" · ")}</div>` : `<h2>Next session</h2><div class="empty">No suggestion for this exercise.</div>`}</div>
      <div class="card"><h2>Plateau check</h2><div style="margin-bottom:8px">${statusChip(p.status)}</div>
        <div class="muted" style="font-size:13px;line-height:1.6">${p.sessions_in_window} sessions in the last 3 weeks<br>Last weight increase: ${p.last_increase ? day(p.last_increase) + ` (${p.days_since_increase} days ago)` : "–"}<br>Top weight ever: ${fmt(p.all_time_top, 2)}</div></div>
      <div class="card"><h2>Progress</h2>
        <div class="tile"><div class="v">${pr.kg_e1rm_per_month == null ? "–" : (pr.kg_e1rm_per_month > 0 ? "+" : "") + fmt(pr.kg_e1rm_per_month, 2)}</div><div class="c">kg e1RM per month, last ${pr.window_days} days</div></div>
        <div class="muted" style="font-size:12px;margin-top:10px;line-height:1.6">${pr.best_90_days ? `Best 90 days from ${day(pr.best_90_days.from)}: <span class="volt">+${pr.best_90_days.kg_per_month}</span>/mo<br>Worst from ${day(pr.worst_90_days.from)}: <span class="orange">${pr.worst_90_days.kg_per_month}</span>/mo` : ""}</div></div>
    </div>
    <div class="card" style="margin-top:16px">
      <div style="display:flex;justify-content:space-between;align-items:center"><h2 style="margin:0">History</h2>
        <div class="seg" id="metric"><button data-m="e1rm" class="on">Est. 1RM</button><button data-m="heaviest">Heaviest</button><button data-m="volume">Volume</button></div></div>
      <div class="chart tall" id="exchart"></div>
      <div class="faint" style="font-size:12px">Click a point to see that session.</div>
    </div>
    <div class="grid g2" style="margin-top:16px">
      <div class="card"><h2>Records</h2><table>${mark("Heaviest", r.heaviest)}${mark("Best est. 1RM", r.best_e1rm)}${mark("Best session volume", r.best_volume)}</table>
        ${r.rep_records.length ? `<details style="margin-top:10px"><summary class="muted" style="cursor:pointer;font-size:13px">Rep records by load (${r.rep_records.length})</summary><table>${r.rep_records.map(m => mark(fmt(m.kg, 2) + " kg", { ...m, kg: m.reps, reps: null }, "reps")).join("")}</table></details>` : ""}</div>
      <div class="card"><h2>Weak-point check</h2>${d.weak_points.map(w => `
        <div style="padding:8px 0;border-bottom:1px solid #ffffff08"><div style="display:flex;justify-content:space-between"><b>${muscleName(w.muscle)}</b><span class="num ${w.likely_weak_point ? "orange" : "muted"}">${w.weekly_sets} sets/wk</span></div>
        ${w.reasons.length ? `<div class="orange" style="font-size:12px">${w.reasons.map(esc).join("; ")}</div>` : ""}
        <div class="faint" style="font-size:12px">${w.other_exercises.map(o => esc(o.name) + " (" + o.status + ")").join(", ") || "No other exercise for it in the last 3 weeks"}</div></div>`).join("")}</div>
      <div class="card"><h2>After breaks</h2>${d.detraining.length ? `<table><tr><th>Break</th><th>Before</th><th>First back</th><th>Sessions to recover</th></tr>${d.detraining.map(x => `<tr><td>${day(x.from)} · ${x.break_days} d</td><td>${x.e1rm_before}</td><td>${x.e1rm_first_back} <span class="faint">(${x.loss_pct > 0 ? "−" + x.loss_pct : "+" + -x.loss_pct}%)</span></td><td>${x.sessions_to_recover ?? "not yet"}</td></tr>`).join("")}</table>` : `<div class="empty">No breaks around this lift.</div>`}</div>
      <div class="card"><h2>Machine and formula</h2>
        <div class="muted" style="font-size:13px;line-height:1.7">Load step: <b class="volt">${inc.step ?? "–"} ${inc.unit ?? ""}</b> <span class="faint">(learnt from ${inc.loads_seen ?? 0} loads you have used, ${Math.round((inc.confidence || 0) * 100)}% of steps)</span><br>
        1RM formula spread on this lift: ${Object.entries(f.mean_spread_pct).map(([k, v]) => `${k.replace("_", " ")} ${v ?? "–"}%`).join(" · ")}<br><span class="faint">${esc(f.caveat || "")}</span></div></div>
    </div>
    <div class="card" style="margin-top:16px"><h2>Sessions</h2><table>${d.sessions.slice(0, 40).map(s => `<tr class="click" data-w="${s.workout_id}"><td class="muted" style="width:120px">${day(s.date)}</td><td><div class="setline">${s.sets.map(x => `<span class="set ${x.type}">${x.type === "warmUp" ? "W " : x.type === "drop" ? "D " : ""}${fmt(x.kg, 2)}×${x.reps}${x.rir != null ? " @" + x.rir : ""}</span>`).join("")}</div></td></tr>`).join("")}</table></div>`;
  const metric = { e1rm: ["e1rm", "kg"], heaviest: ["heaviest", "kg"], volume: ["volume", "kg"] };
  const c = chart($("#exchart"), {});
  const plot = m => {
    const pts = d.points.filter(x => x[m] != null && x[m] > 0);
    c.setOption({
      xAxis: axis({ type: "time" }), yAxis: axis({ type: "value", scale: true }),
      dataZoom: [{ type: "inside" }, { type: "slider", height: 18, bottom: 0, borderColor: LINE, textStyle: { color: DIM } }],
      grid: { left: 50, right: 16, top: 20, bottom: 50 },
      series: [{ type: "line", showSymbol: true, symbolSize: 6, data: pts.map(x => ({ value: [x.date, +x[m].toFixed(2)], workout: x.workout_id })),
        lineStyle: { color: VOLT, width: 2 }, itemStyle: { color: VOLT }, areaStyle: { color: "rgba(199,242,66,.08)" } }],
    }, true);
  };
  plot("e1rm");
  c.on("click", ev => ev.data?.workout && openWorkout(ev.data.workout));
  $("#metric").addEventListener("click", ev => {
    if (!ev.target.dataset.m) return;
    [...$("#metric").children].forEach(b => b.classList.toggle("on", b === ev.target));
    plot(metric[ev.target.dataset.m][0]);
  });
  $("#detail").addEventListener("click", ev => { const tr = ev.target.closest("[data-w]"); if (tr) openWorkout(tr.dataset.w); });
}

// Workout drawer

async function openWorkout(id) {
  const w = await api("workout/" + encodeURIComponent(id));
  const dr = $("#drawer");
  dr.innerHTML = `<button class="close" onclick="closeDrawer()">Close</button><h1 style="font-size:22px">${esc(w.title)}</h1>
    <p class="sub">${day(w.date)} · ${w.minutes} min${w.effort ? " · effort " + w.effort + "/10" : ""}</p>
    ${w.note ? `<div class="note" style="margin-bottom:12px">${esc(w.note)}</div>` : ""}
    ${w.exercises.map(x => `<div class="card" style="margin-bottom:10px"><a href="#/exercises/${encodeURIComponent(x.id)}"><b>${esc(x.name)}</b></a>
      ${x.note ? `<div class="note" style="margin:8px 0">${esc(x.note)}</div>` : ""}
      <div class="setline" style="margin-top:8px">${x.sets.map(s => `<span class="set ${s.type}">${s.type === "warmUp" ? "W " : s.type === "drop" ? "D " : ""}${fmt(s.kg, 2)}×${s.reps}${s.rir != null ? " @" + s.rir : ""}</span>`).join("")}</div></div>`).join("")}`;
  dr.classList.remove("hidden");
}
function closeDrawer() { $("#drawer").classList.add("hidden"); }
window.closeDrawer = closeDrawer;
document.addEventListener("keydown", e => e.key === "Escape" && closeDrawer());

// Muscles

pages.muscles = async () => {
  const { weekly, balance } = await api("muscles?weeks=12");
  const muscles = Object.keys(weekly.muscles).sort((a, b) => weekly.muscles[b].at(-1) - weekly.muscles[a].at(-1));
  const [lo, hi] = weekly.band;
  main.innerHTML = `<h1>Muscles</h1><p class="sub">Fractional hard sets per week (1 per primary muscle, ½ per secondary). Target band ${lo}–${hi}.</p>
    <div class="card"><h2>Last 12 weeks</h2><div class="chart" id="heat" style="height:${Math.max(300, muscles.length * 30 + 60)}px"></div></div>
    <div class="grid g2" style="margin-top:16px">
      <div class="card"><h2>This week against the band</h2><div class="chart tall" id="band"></div></div>
      <div class="card"><h2>Balance · last 4 weeks</h2><table>
        <tr><td>Push sets</td><td>${balance.push_pull.push}</td><td>Pull sets</td><td>${balance.push_pull.pull}</td><td class="volt">${balance.push_pull.ratio ?? "–"}×</td></tr>
        <tr><td>Upper sets</td><td>${balance.upper_lower.upper}</td><td>Lower sets</td><td>${balance.upper_lower.lower}</td><td class="volt">${balance.upper_lower.ratio ?? "–"}×</td></tr>
        <tr><td colspan="4">Quads : hamstrings</td><td class="volt">${balance.quads_hamstrings.ratio ?? "–"}×</td></tr>
        <tr><td colspan="4">Chest : back</td><td class="volt">${balance.chest_back.ratio ?? "–"}×</td></tr></table>
        <p class="faint" style="font-size:12px;line-height:1.5">Around 1× is even. Far from it in either direction is worth a look, not automatically a problem.</p></div>
    </div>`;
  const data = [];
  muscles.forEach((m, y) => weekly.muscles[m].forEach((v, x) => data.push([x, y, v])));
  chart($("#heat"), {
    grid: { left: 110, right: 20, top: 10, bottom: 60 },
    tooltip: { trigger: "item", formatter: p => `${muscleName(muscles[p.value[1]])}, week of ${dayShort(weekly.weeks[p.value[0]])}: ${p.value[2]} sets` },
    xAxis: axis({ type: "category", data: weekly.weeks.map(dayShort), splitArea: { show: false } }),
    yAxis: axis({ type: "category", data: muscles.map(muscleName) }),
    visualMap: { type: "piecewise", orient: "horizontal", left: "center", bottom: 0, textStyle: { color: DIM },
      pieces: [{ max: 0.01, color: "#1f1f23", label: "0" }, { min: 0.01, max: lo, color: "#4a5a1f", label: `under ${lo}` },
        { min: lo, max: hi, color: VOLT, label: `${lo}–${hi}` }, { min: hi, color: ORANGE, label: `over ${hi}` }] },
    series: [{ type: "heatmap", data, label: { show: true, color: "#000", fontSize: 10, formatter: p => p.value[2] ? p.value[2] : "" } }],
  });
  const now = muscles.map(m => weekly.muscles[m].at(-1));
  chart($("#band"), {
    grid: { left: 110, right: 30, top: 10, bottom: 24 },
    xAxis: axis({ type: "value" }), yAxis: axis({ type: "category", data: muscles.map(muscleName), inverse: true }),
    series: [{ type: "bar", data: now.map(v => ({ value: v, itemStyle: { color: v < lo ? "#4a5a1f" : v > hi ? ORANGE : VOLT, borderRadius: 4 } })),
      markArea: { silent: true, itemStyle: { color: "rgba(199,242,66,.07)" }, data: [[{ xAxis: lo }, { xAxis: hi }]] } }],
  });
};

// History

pages.history = async () => {
  const rows = await api("history");
  main.innerHTML = `<h1>History</h1><p class="sub">${rows.length} finished workouts. Click one for its sets.</p>
    <div class="card"><input type="search" id="hq" placeholder="Search titles and exercises"><table id="ht" style="margin-top:10px"></table></div>`;
  const draw = () => {
    const q = $("#hq").value.toLowerCase();
    $("#ht").innerHTML = `<tr><th>Date</th><th>Workout</th><th>Min</th><th>Sets</th><th>Volume</th><th>Exercises</th></tr>` +
      rows.filter(r => !q || r.title.toLowerCase().includes(q) || r.exercises.join(" ").toLowerCase().includes(q)).slice(0, 300)
        .map(r => `<tr class="click" data-w="${r.id}"><td>${day(r.date)}</td><td>${esc(r.title)}</td><td>${r.minutes}</td><td>${r.sets}</td><td>${fmt(r.volume_kg)} kg</td><td class="faint" style="max-width:380px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${esc(r.exercises.join(", "))}</td></tr>`).join("");
  };
  $("#hq").addEventListener("input", draw);
  $("#ht").addEventListener("click", ev => { const tr = ev.target.closest("[data-w]"); if (tr) openWorkout(tr.dataset.w); });
  draw();
};

// Rule lab (S2 extends this page with back-tests)

pages.lab = async () => {
  const f = await api("formulas");
  main.innerHTML = `<h1>Rule lab</h1><p class="sub">Testing rules on your own history before the phone uses them.</p>
    <div class="grid g2">
      <div class="card"><h2>1RM formula lab</h2><div class="chart" id="form"></div>
        <p class="muted" style="font-size:13px;line-height:1.55">Within one session, different weight × rep sets of the same lift should estimate the same 1RM. Lower spread = more consistent on your data.
        Compared over ${fmt(f.sessions_compared)} sessions; most consistent: <b class="volt">${esc(f.most_consistent)}</b>.</p>
        ${f.caveat ? `<div class="warn">${esc(f.caveat)}</div>` : ""}</div>
      <div class="card soon"><h2>Progression back-tests</h2>Replaying double progression, linear-with-deload and stall rules over four years of sessions, scoring how often each called a real plateau and how often it raised the weight too soon. Coming in the next stage (S2).</div>
    </div>`;
  const names = Object.keys(f.mean_spread_pct);
  chart($("#form"), {
    xAxis: axis({ type: "category", data: names.map(n => n.replace("_", " ")) }), yAxis: axis({ type: "value", axisLabel: { color: DIM, formatter: "{value}%" } }),
    series: [{ type: "bar", data: names.map(n => ({ value: f.mean_spread_pct[n], itemStyle: { color: n === f.most_consistent ? VOLT : "#4a5a1f", borderRadius: [6, 6, 0, 0] } })), label: { show: true, position: "top", color: DIM, formatter: "{c}%" } }],
  });
};

pages.notebooks = async () => {
  main.innerHTML = `<h1>Notebooks</h1><p class="sub">Your own code on the same data and functions.</p>
    <div class="soon">The Lab opens marimo notebooks with the loaded history and every analysis function ready to use, and saves custom metrics back to the dashboards. Coming in stage S3.</div>`;
};

pages.ask = async () => {
  main.innerHTML = `<h1>Ask</h1><p class="sub">Questions about your training, answered from figures the studio computed.</p>
    <div class="soon">Ask-your-data, the weekly review and notes mining, with Claude or a local model. Coming in stage S4.</div>`;
};

// Settings

const SETTING_HELP = {
  plateau_days: ["Plateau window (days)", "No weight increase between sessions for this long, with continuous training, is a plateau."],
  volume_band: ["Weekly sets band", "Fractional hard sets per muscle per week; research default 10–20."],
  break_days: ["Break length (days)", "A gap this long between workouts counts as a break."],
  progress_window_days: ["Progress window (days)", "Window for the kg-per-month progress rate."],
  deload_fraction: ["Deload size", "Fraction to drop the weight by on a plateau (0.10 = 10%)."],
  default_rep_range: ["Default rep range", "Used for exercises that aren't in the program."],
  week_starts_monday: ["Week starts Monday", "Otherwise Sunday, like the app's default."],
};
pages.settings = async () => {
  const [s, st] = await Promise.all([api("settings"), api("status")]);
  main.innerHTML = `<h1>Settings</h1><p class="sub">Every threshold the analyses use. Saved on this Mac only.</p>
    <div class="card">${Object.entries(SETTING_HELP).map(([k, [label, help]]) => {
      const v = s[k];
      const input = Array.isArray(v) ? `<div style="display:flex;gap:6px"><input type="number" step="any" data-k="${k}" data-i="0" value="${v[0]}"><input type="number" step="any" data-k="${k}" data-i="1" value="${v[1]}"></div>`
        : typeof v === "boolean" ? `<select data-k="${k}"><option value="false" ${!v ? "selected" : ""}>No</option><option value="true" ${v ? "selected" : ""}>Yes</option></select>`
        : `<input type="number" step="any" data-k="${k}" value="${v}">`;
      return `<div class="field"><div><div>${label}</div><div class="help">${help}</div></div>${input}</div>`;
    }).join("")}
    <div style="margin-top:16px;display:flex;gap:10px"><button class="primary" id="save">Save</button><span id="saved" class="faint" style="align-self:center"></span></div></div>
    <div class="card" style="margin-top:16px"><h2>Backup</h2><div class="muted" style="font-size:13px;line-height:1.7">Loaded: ${esc(st.backup || "none")}<br>Watching: ${st.folders.map(esc).join("<br>")}</div>
      <p class="faint" style="font-size:12px;line-height:1.5">To update automatically, choose a folder inside iCloud Drive in the app (Settings → Backups &amp; recovery). Any iCloud Drive folder whose name contains "GymApp" is watched.</p>
      <button id="reload">Reload newest backup</button></div>`;
  $("#save").onclick = async () => {
    const out = {};
    document.querySelectorAll("[data-k]").forEach(el => {
      const k = el.dataset.k, raw = el.value;
      const val = raw === "true" ? true : raw === "false" ? false : Number(raw);
      if (el.dataset.i != null) { out[k] = out[k] || [...s[k]]; out[k][+el.dataset.i] = val; } else out[k] = val;
    });
    await api("settings", { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify(out) });
    exerciseIndex = null;
    $("#saved").textContent = "Saved. Every page now uses these values.";
  };
  $("#reload").onclick = async () => { await api("reload", { method: "POST" }); exerciseIndex = null; refreshStatus(); };
};

refreshStatus();
setInterval(refreshStatus, 30000);
route();
