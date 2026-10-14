// GymApp Studio interface. Plain JavaScript: one router, one fetch helper, one renderer per page.
const $ = (sel, el = document) => el.querySelector(sel);
const main = $("#main");
const VOLT = "#c7f242", DIM = "#9a9aa3", LINE = "#2e2e33", ORANGE = "#ff9f5a", BLUE = "#73a9ff";
const charts = [];
let navigationEpoch = 0;

async function api(path, options) {
  const epoch = navigationEpoch;
  const r = await fetch("/api/" + path, options);
  const body = await r.json();
  if (epoch !== navigationEpoch && path !== "status") throw new DOMException("Navigation changed", "AbortError");
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
  const epoch = ++navigationEpoch;
  charts.splice(0).forEach(c => c.dispose());
  closeDrawer();
  const [page, ...rest] = (location.hash.slice(2) || "overview").split("/");
  document.querySelectorAll("nav a").forEach(a => a.classList.toggle("active", a.dataset.page === page));
  main.innerHTML = `<div class="empty">Loading…</div>`;
  try {
    await (pages[page] || pages.overview)(decodeURIComponent(rest.join("/")));
  } catch (e) {
    if (epoch !== navigationEpoch || e.name === "AbortError") return;
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
  const custom = await api("lab/metrics");
  main.innerHTML = `
    <h1>Overview</h1>
    <p class="sub">${fmt(o.totals.workouts)} workouts and ${fmt(o.totals.sets)} sets since ${day(o.totals.since)}.</p>
    <div class="grid g4">
      <div class="card tile"><div class="k">This week</div><div class="v">${o.this_week.workouts}</div><div class="c">${fmt(o.this_week.volume_kg)} kg volume</div></div>
      <div class="card tile"><div class="k">Streak</div><div class="v">${o.consistency.current_streak_weeks} wk</div><div class="c">${o.consistency.average_per_week} sessions / week, last 26 weeks</div></div>
      <div class="card tile"><div class="k">Plateaus</div><div class="v ${o.plateaus.length ? "orange" : ""}">${o.plateaus.length}</div><div class="c">3 weeks without a weight increase</div></div>
      <div class="card tile"><div class="k">Last workout</div><div class="v" style="font-size:20px">${esc(o.last_workout?.title || "–")}</div><div class="c">${o.last_workout ? day(o.last_workout.date) + " · " + fmt(o.last_workout.volume_kg) + " kg" : ""}</div></div>
    </div>
    <div id="custom-metrics" class="grid g4" style="margin-top:16px">${custom.metrics.map(m => `<div class="card tile"><div class="k">${esc(m.name)}</div><div class="v">${fmt(m.value)}</div><div class="c">${esc(m.unit)}${m.stale ? " · older snapshot" : ""}</div><p class="sub">${esc(m.description)}</p></div>`).join("")}</div>
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
    </div>
    ${o.steps ? `<div class="card" style="margin-top:16px"><h2>Steps · last 30 days</h2>
      <p class="sub">${fmt(o.steps.daily_average)} a day from Apple Health${o.body_weight ? ` · body weight ${fmt(o.body_weight[1], 1)} kg on ${day(o.body_weight[0])}` : ""}</p>
      <div class="chart" id="steps"></div></div>` : ""}`;
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
  if (o.steps) chart($("#steps"), {
    xAxis: axis({ type: "category", data: o.steps.days.map(d => dayShort(d.date)) }),
    yAxis: axis({ type: "value" }),
    tooltip: { trigger: "axis" },
    series: [{ type: "bar", data: o.steps.days.map(d => d.steps), itemStyle: { color: VOLT, borderRadius: [3, 3, 0, 0] } }],
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

// Rule lab

pages.lab = async () => {
  const [f, exercises] = await Promise.all([api("formulas"), api("exercises")]);
  main.innerHTML = `<h1>Rule lab</h1><p class="sub">Testing rules on your own history before the phone uses them.</p>
    <div class="grid g2">
      <div class="card"><h2>1RM formula lab</h2><div class="chart" id="form"></div>
        <p class="muted" style="font-size:13px;line-height:1.55">Within one session, different weight × rep sets of the same lift should estimate the same 1RM. Lower spread = more consistent on your data.
        Compared over ${fmt(f.sessions_compared)} sessions; most consistent: <b class="volt">${esc(f.most_consistent)}</b>.</p>
        ${f.caveat ? `<div class="warn">${esc(f.caveat)}</div>` : ""}</div>
      <div class="card"><h2>Progression replay</h2><p class="muted">Compare rules against sessions that actually happened. Earlier sessions generate targets; later sessions score them.</p>
        <label>Exercise<select id="rule-exercise"><option value="">All trained exercises</option>${exercises.map(e => `<option value="${esc(e.id)}">${esc(e.name)}</option>`).join("")}</select></label>
        <div class="grid g2" style="margin-top:12px"><label>Outcome window (days)<input id="rule-days" type="number" min="7" max="180" value="21"></label>
        <label>Later sessions held out (%)<input id="rule-holdout" type="number" min="10" max="80" value="30"></label></div>
        <button class="primary" id="rule-run" style="margin-top:12px">Run comparison</button><span id="rule-error" role="status" class="orange"></span>
        <p class="faint">Rep ranges come from the workout snapshot, or the default range in Settings. Load steps use earlier logged loads only.</p></div>
    </div><div id="rule-results" style="margin-top:16px"></div>`;
  const names = Object.keys(f.mean_spread_pct);
  chart($("#form"), {
    xAxis: axis({ type: "category", data: names.map(n => n.replace("_", " ")) }), yAxis: axis({ type: "value", axisLabel: { color: DIM, formatter: "{value}%" } }),
    series: [{ type: "bar", data: names.map(n => ({ value: f.mean_spread_pct[n], itemStyle: { color: n === f.most_consistent ? VOLT : "#4a5a1f", borderRadius: [6, 6, 0, 0] } })), label: { show: true, position: "top", color: DIM, formatter: "{c}%" } }],
  });
  let offset = 0, selectedRule = "double_progression";
  const run = async () => {
    const button = $("#rule-run"), errorBox = $("#rule-error");
    button.disabled = true; errorBox.textContent = "";
    try {
      const params = new URLSearchParams({ outcome_days: $("#rule-days").value, holdout_fraction: Number($("#rule-holdout").value) / 100,
        rule: selectedRule, offset, limit: 100 });
      if ($("#rule-exercise").value) params.set("exercise_id", $("#rule-exercise").value);
      const result = await api("rules?" + params);
      renderRuleReplay(result, selectedRule, offset, async (rule, nextOffset) => { selectedRule = rule; offset = nextOffset; await run(); });
    } catch (error) { if (error.name !== "AbortError") errorBox.textContent = " " + error.message; }
    finally { button.disabled = false; }
  };
  $("#rule-run").onclick = () => { offset = 0; run(); };
  await run();
};

function renderRuleReplay(result, selectedRule, offset, change) {
  const percent = value => value == null ? "–" : fmt(value * 100, 1) + "%";
  const selected = result.rules.find(r => r.id === selectedRule);
  const target = t => t ? `${fmt(t.weight, 2)} ${esc(t.unit)} × ${t.reps} · ${esc(t.kind)}${t.rir != null ? ` @ ${t.rir} left` : ""}` : "No logged RIR";
  $("#rule-results").innerHTML = `<div class="card"><h2>Later-session holdout comparison</h2>
    <p class="sub">${result.exercises.length} exercises · final ${fmt(result.holdout_fraction * 100)}% of each exercise's exposures · ${result.outcome_days}-day plateau outcome.</p>
    <div class="table-scroll"><table><thead><tr><th>Rule</th><th>Plateau outcomes</th><th>Precision</th><th>Recall</th><th>Balanced accuracy</th><th>Raised targets missed</th></tr></thead><tbody>
    ${result.rules.map(r => { const m = r.holdout; return `<tr><td>${esc(r.name)}</td><td>${m.plateau_evaluated} (${m.true_positive + m.false_negative} plateaus)</td>
      <td>${percent(m.precision)}</td><td>${percent(m.recall)}</td><td>${percent(m.balanced_accuracy)}</td><td>${percent(m.raised_target_miss_rate)} / ${m.raised_targets_evaluated} attempted</td></tr>`; }).join("")}</tbody></table></div>
    <p class="faint">Precision: how many deload calls preceded the defined plateau. Recall: how many defined plateaus were called. Balanced accuracy gives plateau and non-plateau outcomes equal weight. A dash means the denominator is missing. Repeated windows overlap; these are descriptive scores.</p>
    <div class="warn">These results do not prove that following a different rule would improve your gains. No rule is automatically sent to the phone.</div></div>
    <div class="card" style="margin-top:16px"><h2>Inspect the replay</h2>
      <label>Rule<select id="rule-choice">${result.rules.map(r => `<option value="${r.id}" ${r.id === selectedRule ? "selected" : ""}>${esc(r.name)}</option>`).join("")}</select></label>
      <p class="muted">All history: ${selected.metrics.predictions} targets; ${selected.metrics.abstained} abstentions. Exact targets attempted: ${selected.metrics.targets_met} met, ${selected.metrics.targets_missed} missed. Other weights do not reveal whether an untried target was possible.</p>
      <div class="table-scroll"><table id="rule-trials"><thead><tr><th>Session</th><th>Observed sets</th><th>Next target</th><th>Next exposure</th><th>Later plateau?</th></tr></thead><tbody>
      ${selected.trials.map(r => `<tr class="click" data-w="${esc(r.workout_id)}"><td>${day(r.date)}<br>${esc(r.name)}<br><span class="faint">${r.fold}</span></td>
        <td>${r.last.map(x => `${fmt(x.weight, 2)} ${esc(x.unit)} × ${x.reps}${x.rir != null ? ` @ ${x.rir}` : ""}`).join("<br>")}</td>
        <td>${target(r.target)}<br><span class="faint">${esc(r.target?.reason || "Effort rule abstained")}</span></td><td>${esc(r.next_result)}</td>
        <td>${r.observed_plateau == null ? "Unscored" : r.observed_plateau ? "Yes" : "No"}</td></tr>`).join("") || `<tr><td colspan="5">No eligible exposures.</td></tr>`}</tbody></table></div>
      <div style="display:flex;gap:10px;margin-top:12px"><button id="rule-prev" ${offset === 0 ? "disabled" : ""}>Previous</button><button id="rule-next" ${offset + 100 >= selected.trial_count ? "disabled" : ""}>Next</button><span class="faint">${selected.trial_count ? offset + 1 : 0}–${Math.min(offset + 100, selected.trial_count)} of ${selected.trial_count}</span></div>
      <details style="margin-top:16px"><summary>Method and limits</summary><p>${esc(result.method)}</p><ul>${result.limitations.map(x => `<li>${esc(x)}</li>`).join("")}</ul></details></div>`;
  $("#rule-choice").onchange = event => change(event.target.value, 0);
  $("#rule-prev").onclick = () => change(selectedRule, Math.max(0, offset - 100));
  $("#rule-next").onclick = () => change(selectedRule, offset + 100);
  $("#rule-trials").onclick = event => { const row = event.target.closest("[data-w]"); if (row) openWorkout(row.dataset.w); };
}

pages.notebooks = async () => {
  const [listing, context] = await Promise.all([api("lab/notebooks"), api("lab/context")]);
  main.innerHTML = `<h1>Notebooks</h1><p class="sub">Editable Python on the same saved snapshot and tested analysis functions.</p>
    <div class="card"><h2>Your notebooks</h2><p class="sub">Saved on this Mac: ${esc(listing.folder)}</p>
    <label>Notebook <select id="notebook-select">${listing.notebooks.map(n => `<option value="${esc(n.filename)}">${esc(n.name)}</option>`).join("")}</select></label>
    <button class="btn" id="notebook-open">Open editor</button>
    <label>New notebook name <input id="notebook-name" placeholder="my_analysis"></label><button class="btn" id="notebook-create">Create notebook</button>
    <p id="notebook-error" class="orange"></p><p id="notebook-link"></p></div>
    <p class="sub">Notebooks run your Python locally. The supplied history and tables are read-only copies. Publish a custom metric to show it on Overview.</p>`;
  const errorBox = $("#notebook-error");
  const write = async (path, values) => api(path, {method:"POST", headers:{"Content-Type":"application/json", "X-Studio-Token":context.write_token}, body:JSON.stringify(values || {})});
  $("#notebook-create").onclick = async () => {
    try { await write("lab/notebooks", {name:$("#notebook-name").value}); await pages.notebooks(); }
    catch(e) { if(e.name !== "AbortError") errorBox.textContent=e.message; }
  };
  $("#notebook-open").onclick = async () => {
    const filename = $("#notebook-select").value;
    const linkBox = $("#notebook-link");
    try { const editor = await write("lab/start");
      const url = new URL(editor.url); url.searchParams.set("file",filename);
      linkBox.innerHTML = `<a class="btn" href="${esc(url.href)}" target="_blank" rel="noopener">Open ${esc(filename)} in the notebook editor</a>`;
    } catch(e) { if(e.name !== "AbortError") errorBox.textContent=e.message; }
  };
};

const askChat = { turns: [] };
pages.ask = async () => {
  const cfg = await api("ask/config");
  const pref = JSON.parse(localStorage.getItem("askPrefs") || "{}");
  const provider = pref.provider || (cfg.has_key ? "claude" : "local");
  main.innerHTML = `<h1>Ask</h1><p class="sub">Questions about your training. The model calls the studio's own calculations and explains them; it never makes up figures.</p>
    <div class="card" style="display:flex;flex-wrap:wrap;gap:12px;align-items:center">
      <div class="seg" id="prov"><button data-v="claude">Claude</button><button data-v="local">Local model</button></div>
      <select id="model" style="width:220px"></select>
      <div class="seg" id="mode"><button data-v="summaries">Summaries only</button><button data-v="full">Full access</button></div>
      <span id="modehelp" class="faint" style="font-size:12px;flex:1;min-width:220px"></span>
    </div>
    ${cfg.has_key ? "" : `<div class="warn" style="margin-top:12px">No Claude API key yet. Add one in Settings, or use the local model (${cfg.local_models.length ? esc(cfg.local_models.join(", ")) : "Ollama isn't running"}).</div>`}
    <div class="card" style="margin-top:16px"><div id="chat" style="display:flex;flex-direction:column;gap:14px;min-height:120px"></div>
      <div style="display:flex;flex-wrap:wrap;gap:8px;margin:14px 0">${Object.entries(cfg.presets).map(([k]) => `<button data-preset="${k}">${{ weekly: "Weekly review", plateaus: "Plateaus and weak points", balance: "Is my training balanced?", notes: "Themes in my notes" }[k] || k}</button>`).join("")}
        <button id="clear" style="margin-left:auto">New chat</button></div>
      <div style="display:flex;gap:10px"><textarea id="q" rows="2" placeholder="e.g. Why has my bench stopped going up? What should I change in Full Body 2?"></textarea><button class="primary" id="send" style="align-self:stretch">Ask</button></div>
    </div>`;
  const st = { provider, mode: pref.mode || "summaries", model: pref.model };
  const models = () => st.provider === "claude" ? cfg.claude_models : (cfg.local_models.length ? cfg.local_models : ["llama3.2"]);
  const sync = () => {
    [...$("#prov").children].forEach(b => b.classList.toggle("on", b.dataset.v === st.provider));
    [...$("#mode").children].forEach(b => b.classList.toggle("on", b.dataset.v === st.mode));
    const ms = models(); if (!ms.includes(st.model)) st.model = ms[0];
    $("#model").innerHTML = ms.map(m => `<option ${m === st.model ? "selected" : ""}>${esc(m)}</option>`).join("");
    $("#modehelp").textContent = st.mode === "full"
      ? (st.provider === "claude" ? "Full access: Claude may read any table and your notes, sent to Anthropic." : "Full access: the local model may read any table and your notes. Nothing leaves this Mac.")
      : (st.provider === "claude" ? "Summaries only: Claude sees computed figures, never raw sets or notes." : "Summaries only, on this Mac.");
    localStorage.setItem("askPrefs", JSON.stringify(st));
  };
  $("#prov").onclick = e => { if (e.target.dataset.v) { st.provider = e.target.dataset.v; sync(); } };
  $("#mode").onclick = e => { if (e.target.dataset.v) { st.mode = e.target.dataset.v; sync(); } };
  $("#model").onchange = e => { st.model = e.target.value; sync(); };
  const md = t => esc(t).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>").replace(/^#+ (.*)$/gm, "<b>$1</b>").replace(/^[-•] (.*)$/gm, "• $1").replace(/\n/g, "<br>");
  const draw = () => {
    $("#chat").innerHTML = askChat.turns.map(t => t.role === "user"
      ? `<div style="align-self:flex-end;max-width:75%;background:var(--volt-dim);color:var(--text);padding:10px 14px;border-radius:14px">${esc(t.content)}</div>`
      : `<div style="max-width:90%;line-height:1.55;font-size:14px">${t.error ? `<div class="warn">${esc(t.error)}</div>` : md(t.content)}
          ${t.unverified?.length ? `<div class="warn" style="margin-top:8px">Unverified: ${t.unverified.map(esc).join(", ")} ${t.unverified.length > 1 ? "don't" : "doesn't"} appear in any calculation the model ran. Treat ${t.unverified.length > 1 ? "them" : "it"} as unreliable.</div>` : ""}
          ${!t.error && t.content && t.content !== "Thinking…" && !t.calls?.length ? `<div class="faint" style="font-size:12px;margin-top:6px">No calculations were used for this answer.</div>` : ""}
          ${t.calls?.length ? `<details style="margin-top:6px"><summary class="faint" style="cursor:pointer;font-size:12px">${t.calls.length} calculation${t.calls.length > 1 ? "s" : ""} used · ${esc(t.model || "")}</summary><div class="faint" style="font-size:12px;margin-top:4px">${t.calls.map(c => esc(c.tool) + (Object.keys(c.input || {}).length ? " " + esc(JSON.stringify(c.input)) : "")).join("<br>")}</div></details>` : ""}</div>`).join("")
      || `<div class="empty">Ask anything about your training, or start with a button below.</div>`;
  };
  const send = async (question) => {
    question = (question || $("#q").value).trim(); if (!question) return;
    $("#q").value = "";
    const history = askChat.turns.filter(t => !t.error).map(t => ({ role: t.role, content: t.content }));
    askChat.turns.push({ role: "user", content: question }, { role: "assistant", content: "Thinking…" });
    draw(); $("#send").disabled = true;
    try {
      const r = await api("ask", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ question, history, provider: st.provider, model: st.model, mode: st.mode }) });
      askChat.turns[askChat.turns.length - 1] = { role: "assistant", content: r.answer, calls: r.tool_calls, model: r.model, unverified: r.unverified };
    } catch (e) {
      askChat.turns[askChat.turns.length - 1] = { role: "assistant", content: "", error: e.message };
    }
    $("#send").disabled = false; draw();
  };
  $("#send").onclick = () => send();
  $("#q").onkeydown = e => { if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) send(); };
  document.querySelectorAll("[data-preset]").forEach(b => b.onclick = () => {
    if (b.dataset.preset === "notes" && st.mode !== "full") { st.mode = "full"; sync(); }
    send(cfg.presets[b.dataset.preset]);
  });
  $("#clear").onclick = () => { askChat.turns = []; draw(); };
  sync(); draw();
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
// Suggestions (card 6.3)

pages.suggestions = async () => {
  const d = await api("suggestions");
  const decided = Object.fromEntries(d.decisions.map(x => [x.id, x]));
  const kindLabel = { target: "Next target", swap: "Swap", note: "Note" };
  const row = (s, box) => `
    <label class="row" style="align-items:flex-start;gap:12px;cursor:${box ? "pointer" : "default"}">
      ${box ? `<input type="checkbox" data-id="${esc(s.id)}" checked style="margin-top:4px">` : ""}
      <div class="grow"><div class="t">${esc(s.title)}</div>
        <div class="s">${esc(s.detail)}</div>
        <div class="s faint">${esc(kindLabel[s.kind])} · ${esc(s.rule)} · ${esc(s.reason)}</div></div>
      ${box ? "" : statusChip(decided[s.id]?.decision || "waiting")}
    </label>`;
  main.innerHTML = `<h1>Suggestions</h1>
    <p class="sub">Drafted from the plateau check, the weak-point check and next targets. Publishing writes ${esc("GymApp-suggestions.json")} to <code>${esc(d.folder)}</code>; the phone shows each one on Train with its reason, and nothing changes there until you accept it.</p>
    <div class="card"><h2>Drafts</h2>
      ${d.drafts.length ? `<div class="list" id="drafts">${d.drafts.map(s => row(s, true)).join("")}</div>` : `<div class="empty">No new drafts. Every current suggestion is already published or decided.</div>`}
      <h2 style="margin-top:20px">Note</h2>
      <div style="display:grid;gap:8px"><input id="nt" placeholder="Title, e.g. Sleep before heavy days">
        <textarea id="nd" rows="2" placeholder="Detail"></textarea><input id="nr" placeholder="Why (optional)"></div>
      <div style="display:flex;gap:10px;align-items:center;margin-top:14px"><button class="primary" id="pub">Publish selected</button><span id="pubmsg" class="faint"></span></div>
    </div>
    <div class="card" style="margin-top:16px"><h2>On the phone</h2>
      ${d.published.length ? `<div class="list">${d.published.map(s => row(s, false)).join("")}</div>` : `<div class="empty">Nothing published yet.</div>`}
      ${d.decisions.length ? `<h2 style="margin-top:20px">Decided on the phone</h2><table><tr><th>Suggestion</th><th>Decision</th><th>When</th></tr>${d.decisions.map(x => `<tr><td>${esc(x.id)}</td><td>${esc(x.decision)}</td><td>${day(x.decidedAt)}</td></tr>`).join("")}</table>` : ""}
    </div>`;
  $("#pub").onclick = async () => {
    const chosen = new Set([...document.querySelectorAll("#drafts input:checked")].map(i => i.dataset.id));
    const items = [...d.published.filter(s => !decided[s.id]), ...d.drafts.filter(s => chosen.has(s.id))];
    const notes = $("#nt").value.trim() ? [{ title: $("#nt").value, detail: $("#nd").value, reason: $("#nr").value }] : [];
    try {
      const r = await api("suggestions/publish", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ items, notes }) });
      $("#pubmsg").textContent = `Published ${r.published.length}.`;
      setTimeout(route, 600);
    } catch (e) { $("#pubmsg").textContent = e.message; }
  };
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
    <div class="card" style="margin-top:16px"><h2>Claude API key</h2>
      <p class="muted" style="font-size:13px;line-height:1.5">Used only by Ask when Claude is chosen. Stored in this Mac's keychain, never in a file or the repository.</p>
      <div style="display:flex;gap:10px"><input type="password" id="apikey" placeholder="sk-ant-…"><button id="savekey">Save key</button><button id="delkey">Remove</button></div>
      <div id="keystate" class="faint" style="font-size:12px;margin-top:8px"></div></div>
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
    try {
      await api("settings", { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify(out) });
      exerciseIndex = null; $("#saved").textContent = "Saved. Every page now uses these values.";
    } catch (error) { $("#saved").textContent = error.message; }
  };
  const keyState = async () => { const c = await api("ask/config"); $("#keystate").textContent = c.has_key ? "A key is saved." : "No key saved."; };
  keyState();
  const putKey = async key => {
    try { await api("ask/key", { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ key }) }); $("#apikey").value = ""; keyState(); }
    catch (e) { $("#keystate").textContent = e.message; }
  };
  $("#savekey").onclick = () => putKey($("#apikey").value);
  $("#delkey").onclick = () => putKey("");
  $("#reload").onclick = async () => { await api("reload", { method: "POST" }); exerciseIndex = null; refreshStatus(); };
};

refreshStatus();
setInterval(refreshStatus, 30000);
route();
