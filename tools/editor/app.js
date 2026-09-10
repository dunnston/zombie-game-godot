"use strict";
// DEADLINE content editor. Plain JS, no build step, served by
// tools/edit_server.gd. The server is the authority: it validates every save
// and writes the file through DataTable.encode, so nothing here formats JSON
// for disk and nothing here decides whether a save is allowed.

const TOKEN = document.querySelector('meta[name="edit-token"]').content;
const $ = (sel) => document.querySelector(sel);
const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

// Columns and fields that read best first; everything else is alphabetical.
const FIRST = ["name", "label", "category", "subcategory", "status", "kind", "slot", "table", "tier"];
// PROJECT.md §10: 0 is by hand, 1 and 2 the one Workbench and its upgrade.
const BENCH = { 0: "by hand", 1: "Workbench", 2: "Workbench II" };
// The recipe keys the card spells out; any other key shows as a tag.
const RECIPE_KEYS = ["id", "name", "bench", "cost", "give", "xp"];
// Where an item can be defined, in the order a lookup tries them.
const ITEM_TABLES = ["WEAPONS", "GEAR", "CONSUMABLES", "RES", "STRUCTURES"];
const CATEGORY_ORDER = ["Weapons", "Tools", "Clothing/Armor", "Ammo", "Medical Items", "Consumables food", "Consumables misc", "Materials", "Building", "Special Items", "Misc Items"];
// The planned benches from Notion's Workbenches table, and their catalog rows.
const PLANNED_BENCHES = [["Player Menu", null], ["Basic", "basicBench"], ["Advanced", "advancedBench"], ["Tech", "techBench"]];
// Owner-facing views over the tables. Each returns the view's content.
const VIEWS = { Workbenches: viewWorkbenches, Weapons: viewWeapons, Materials: viewMaterials, Tools: viewTools, Ammo: viewAmmo, Catalog: viewCatalog };
// Notion's weapon classes, in its order: six melee, then eight ranged.
const MELEE = ["Improvised", "Blunt", "Bladed", "Axes", "Polearms", "Heavy"];
const RANGED = ["Handguns", "Shotguns", "Rifles", "SMGs", "Assault Rifles", "Precision Rifles", "Bows/Crossbows", "Heavy/Special"];
// The tables whose rows are items, and so have a catalog class and a look.
const CLASSED = ["WEAPONS", "GEAR", "CONSUMABLES", "RES"];

const S = {
  tables: {},   // name -> {name, editable, file, doc, dirty, gitDirty, loadErrors}
  order: [],
  consts: {},
  art: [],      // file names (no .png) present in art/items/
  artVer: Date.now(), // bumped on upload so the browser fetches the new picture
  problems: [], // broken references across all content, from the server
  view: null,   // a key of VIEWS, or null for a table
  cur: null,    // the table the detail pane edits
  sel: null,
  filter: "",
  sort: null,   // {key, up}
  errors: [],   // the server's verdict on the current table's unsaved state
};

// ------------------------------------------------------------------ helpers --

function el(tag, attrs, ...kids) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k.startsWith("on")) n.addEventListener(k.slice(2), v);
    else if (k === "class") n.className = v;
    else if (k === "value") n.value = v;
    else if (k === "checked") n.checked = !!v;
    else n.setAttribute(k, v === true ? "" : v);
  }
  return add(n, ...kids);
}

// DOM append that flattens arrays and skips empty values, the way el() does.
// Plain append() would print "[object HTMLButtonElement]" for an array.
function add(node, ...kids) {
  for (const kid of kids.flat(Infinity)) {
    if (kid == null || kid === false) continue;
    node.append(kid instanceof Node ? kid : String(kid));
  }
  return node;
}

function toast(msg, bad) {
  const t = $("#toast");
  t.textContent = msg;
  t.className = bad ? "bad" : "";
  t.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (t.hidden = true), bad ? 7000 : 4500);
}

function rowsOf(v) {
  if (Array.isArray(v)) return v.map((r, i) => (isObj(r) ? { ...r, id: r.id ?? String(i) } : { id: String(i), value: r }));
  if (isObj(v)) return Object.entries(v).map(([k, r]) => (isObj(r) ? { ...r, id: r.id ?? k } : { id: k, entries: r }));
  return [];
}

function inferFields(rows) {
  const f = {};
  for (const r of rows) {
    for (const [k, v] of Object.entries(r)) {
      if (k === "id" || f[k]) continue;
      f[k] = { type: typeof v === "number" ? "number" : typeof v === "boolean" ? "bool" : typeof v === "string" ? "string" : "json" };
    }
  }
  return f;
}

function orderKeys(keys) {
  const head = FIRST.filter((k) => keys.includes(k));
  return [...head, ...keys.filter((k) => !head.includes(k)).sort()];
}

const cur = () => S.tables[S.cur];
const listRows = (name) => (S.tables[name] ? S.tables[name].doc.rows : []);
const rowById = (name, id) => listRows(name).find((r) => r.id === id);

// Ids a `ref` may name: a table's rows, or a literal list such as AMMO_IDS.
function setIds(name) {
  if (S.tables[name]) return listRows(name).map((r) => r.id);
  const c = S.consts[name];
  return Array.isArray(c) ? c.map(String) : isObj(c) ? Object.keys(c) : [];
}

function get(obj, path) {
  return path.split(".").reduce((o, k) => (o == null ? undefined : o[k]), obj);
}

function fmt(v) {
  if (v === undefined) return "";
  if (typeof v === "boolean") return v ? "✓" : "✗";
  if (typeof v === "object") return JSON.stringify(v);
  return String(v);
}

function groupBy(list, key) {
  const m = new Map();
  for (const x of list) {
    const k = key(x);
    if (!m.has(k)) m.set(k, []);
    m.get(k).push(x);
  }
  return m;
}

// ------------------------------------------------------------ item lookups --

function findItem(id) {
  for (const n of ITEM_TABLES) {
    const r = rowById(n, id);
    if (r) return { table: n, row: r };
  }
  return null;
}
const catalogRow = (id) => rowById("CATALOG", id);
function itemName(id) {
  const f = findItem(id);
  return f ? f.row.name || id : (catalogRow(id) || {}).name || id;
}
// Open an item in the detail pane without leaving the view.
function openItem(id) {
  const f = findItem(id);
  if (f) go(f.table, id, true);
  else if (catalogRow(id)) go("CATALOG", id, true);
}
// The loot grammar: bare resources, `weapon:`, `gear:`, `item:`.
function lootId(id) {
  const f = findItem(id);
  const prefix = { WEAPONS: "weapon:", GEAR: "gear:", CONSUMABLES: "item:" }[f ? f.table : ""];
  return (prefix || "") + id;
}
function outputs(r) {
  const g = r.give || {};
  if (g.weapon) return [{ id: g.weapon, n: 1 }];
  if (g.gear) return [{ id: g.gear, n: 1 }];
  if (g.item) return [{ id: g.item, n: g.n || 1 }];
  if (isObj(g.res)) return Object.entries(g.res).map(([id, n]) => ({ id, n }));
  return [];
}
const recipesMaking = (id) => listRows("RECIPES").filter((r) => outputs(r).some((o) => o.id === id));
const recipesUsing = (id) => listRows("RECIPES").filter((r) => isObj(r.cost) && id in r.cost);
const structuresUsing = (id) => listRows("STRUCTURES").filter((s) => isObj(s.cost) && id in s.cost);
// Every specialised station a structure offers (the Chemistry Station today).
const stationList = () => listRows("STRUCTURES").filter((s) => s.station).map((s) => ({ id: s.station, name: s.name, row: s }));
const stationName = (id) => (stationList().find((s) => s.id === id) || { name: id }).name;
const placeLabel = (r) => (r.station ? stationName(r.station) : BENCH[r.bench] || `bench ${r.bench}`);
const badge = (status) => (status ? el("span", { class: `badge ${String(status).replace(/\s+/g, "-")}` }, status) : "");
const swatch = (c) => (c ? el("span", { class: "sw", style: `background:${c}` }) : "");
const none = () => el("span", { class: "hint" }, "—");
const hit = (q, ...things) => !q || things.some((x) => JSON.stringify(x ?? "").toLowerCase().includes(q));

// ------------------------------------------------------------------- filter --

// Space-separated terms, all of which must hold:
//   kind=gun  ammo=ammoR  dmg>30  crit<=0.05  name~rifle  has:bleed  !has:dur
// and any bare word, which matches anywhere in the row.
function parseFilter(q) {
  const toks = q.match(/"[^"]*"|\S+/g) || [];
  return toks.map((raw) => {
    const t = raw.replace(/^"|"$/g, "");
    let m;
    if ((m = t.match(/^(!|-)?has:(.+)$/))) return (r) => (get(r, m[2]) !== undefined) !== !!m[1];
    if ((m = t.match(/^([\w.]+)(>=|<=|!=|=|>|<|~)(.*)$/))) return (r) => compare(get(r, m[1]), m[2], m[3]);
    const needle = t.toLowerCase();
    return (r) => JSON.stringify(r).toLowerCase().includes(needle);
  });
}

function compare(v, op, want) {
  if (v === undefined) return op === "!=";
  const n = Number(want);
  const num = typeof v === "number" && want !== "" && !Number.isNaN(n);
  const s = (typeof v === "object" ? JSON.stringify(v) : String(v)).toLowerCase();
  const w = want.toLowerCase();
  switch (op) {
    case "=": return num ? v === n : s === w;
    case "!=": return num ? v !== n : s !== w;
    case "~": return s.includes(w);
    case ">": return num && v > n;
    case "<": return num && v < n;
    case ">=": return num && v >= n;
    case "<=": return num && v <= n;
  }
  return false;
}

// -------------------------------------------------------------- server I/O --

async function load() {
  const r = await fetch("/api/tables", { cache: "no-store" });
  if (!r.ok) throw new Error(await r.text());
  const j = await r.json();
  S.order = j.tables.map((t) => t.name);
  S.consts = j.consts;
  S.art = j.art || [];
  S.problems = j.problems || [];
  for (const t of j.tables) {
    if (S.tables[t.name] && S.tables[t.name].dirty) continue; // never drop unsaved work
    if (t.editable) {
      S.tables[t.name] = { name: t.name, editable: true, file: t.file, doc: t.doc, dirty: false, gitDirty: t.dirty, loadErrors: t.errors };
    } else {
      const rows = rowsOf(t.value);
      S.tables[t.name] = { name: t.name, editable: false, doc: { fields: inferFields(rows), rows } };
    }
  }
  if (!S.tables[S.cur]) S.cur = S.order.find((n) => S.tables[n].editable) || S.order[0];
  render();
}

function outDoc(doc) {
  const out = { fields: doc.fields, rows: doc.rows.map((r) => {
    const c = { ...r };
    if (typeof c.notes === "string" && !c.notes.trim()) delete c.notes;
    return c;
  }) };
  if (doc.notes && doc.notes.trim()) out.notes = doc.notes;
  return out;
}

async function send(method, path, t) {
  const r = await fetch(path, {
    method,
    headers: { "Content-Type": "application/json", "X-Edit-Token": TOKEN },
    body: JSON.stringify(outDoc(t.doc)),
  });
  const text = await r.text();
  let j;
  try { j = JSON.parse(text); } catch { j = { errors: [text || `HTTP ${r.status}`] }; }
  return { ok: r.ok, status: r.status, j };
}

let vTimer = null;
function changed() {
  const t = cur();
  t.dirty = true;
  clearTimeout(vTimer);
  vTimer = setTimeout(validate, 350);
  renderNav();
  renderList();
}

async function validate() {
  const t = cur();
  if (!t || !t.editable || !t.dirty) return;
  const { j } = await send("POST", `/api/validate/${t.name}`, t);
  S.errors = j.errors || [];
  renderList();
  markFieldErrors();
}

async function save() {
  const t = cur();
  if (!t || !t.editable || !t.dirty) return;
  clearTimeout(vTimer);
  const { ok, j } = await send("PUT", `/api/table/${t.name}`, t);
  if (!ok) {
    S.errors = j.errors || [];
    renderList();
    markFieldErrors();
    toast(`Not saved: ${S.errors.length} problem${S.errors.length === 1 ? "" : "s"}. Fix them and try again.`, true);
    return;
  }
  t.dirty = false;
  S.errors = [];
  toast(`Saved ${j.file} (+${j.diff.added} −${j.diff.removed} lines). Commit it with git when you're happy.`);
  await load();
}

async function revert() {
  const t = cur();
  if (!t.dirty || !confirm(`Throw away unsaved changes to ${t.name}?`)) return;
  t.dirty = false;
  S.errors = [];
  await load();
}

// --------------------------------------------------------------- rendering --

function render() {
  renderStatus();
  renderNav();
  renderList();
  renderDetail();
}

// The middle pane: a view, or the current table's grid.
function renderList() {
  renderHead();
  renderProblems();
  if (S.view) renderViewBody();
  else renderGrid();
}

function renderStatus() {
  const ed = S.order.filter((n) => S.tables[n].editable);
  const git = ed.filter((n) => S.tables[n].gitDirty).map((n) => S.tables[n].file);
  $("#status").replaceChildren();
  add($("#status"),
    `${S.order.length} tables · ${ed.length} editable · the rest still live in config.gd`,
    git.length ? el("span", { class: "warn" }, ` · uncommitted: ${git.join(", ")}`) : "");
}

function renderNav() {
  const mk = (n) => {
    const t = S.tables[n];
    return el("button", { class: !S.view && n === S.cur ? "cur" : "", onclick: () => go(n, null) },
      el("span", {}, n, t.dirty ? el("span", { class: "dot", title: "Unsaved changes" }, " ●") : ""),
      el("span", { class: t.editable ? "n" : "ro" }, t.editable ? t.doc.rows.length : "read-only"));
  };
  const views = Object.keys(VIEWS).map((v) => el("button", { class: S.view === v ? "cur" : "", onclick: () => goView(v) }, el("span", {}, v)));
  const ed = S.order.filter((n) => S.tables[n].editable);
  const ro = S.order.filter((n) => !S.tables[n].editable);
  const nav = $("#tables");
  nav.replaceChildren();
  add(nav, el("h4", {}, "Views"), views, el("h4", {}, "Data files"), ed.map(mk), el("h4", {}, "Still in config.gd"), ro.map(mk));
}

// Save and Revert act on the table the detail pane is editing, from any view.
function editButtons(t) {
  if (!t || !t.editable) return [];
  const blocked = S.errors.length > 0;
  const label = S.view ? ` ${t.name}` : "";
  return [
    el("button", { onclick: revert, disabled: !t.dirty }, `Revert${label}`),
    el("button", { class: "primary", onclick: save, disabled: !t.dirty || blocked,
      title: blocked ? "Fix the problems listed first" : "Save (Ctrl+S)" }, `Save${label}`),
  ];
}

function renderHead() {
  const t = cur();
  const head = $("#head");
  const refocus = document.activeElement && document.activeElement.type === "search";
  const filter = el("input", {
    type: "search", value: S.filter, spellcheck: "false",
    placeholder: S.view ? "filter this view" : "filter: kind=gun ammo=ammoR dmg>30 has:bleed !has:dur rifle",
    oninput: (e) => { S.filter = e.target.value; if (S.view) renderViewBody(); else renderGrid(); },
  });
  head.replaceChildren();
  if (S.view) {
    add(head, el("h2", {}, S.view), filter, editButtons(t));
  } else {
    add(head, el("h2", {}, t.name),
      el("span", { class: "file mono" }, t.editable ? t.file : "read-only — migrate it to edit"),
      filter,
      t.editable ? el("button", { onclick: addRow }, "+ Row") : "",
      editButtons(t));
  }
  if (refocus) filter.focus();
}

function renderProblems() {
  const t = cur();
  const items = [...(t && t.loadErrors ? t.loadErrors : []), ...S.errors];
  const other = S.problems.filter((p) => !items.includes(p));
  const box = $("#problems");
  box.replaceChildren();
  if (items.length) add(box, el("b", {}, "This change cannot be saved yet:"), el("ul", {}, items.map((e) => el("li", {}, e))));
  if (other.length) add(box, el("b", {}, "Already broken in the content on disk:"), el("ul", {}, other.map((e) => el("li", {}, e))));
}

// An item's catalog class ("Blunt", "Salvage"), shown and filtered as if it
// were a column (`class=Blunt`), though it lives in the catalog.
const classOf = (id) => { const c = catalogRow(id); return c ? c.subcategory || c.category : undefined; };
const classed = (t) => CLASSED.includes(t.name) && !!S.tables.CATALOG;
const decorate = (t, r) => (classed(t) ? { ...r, class: classOf(r.id) } : r);

function visibleRows(t) {
  const preds = parseFilter(S.filter);
  let rows = t.doc.rows.filter((r) => { const d = decorate(t, r); return preds.every((p) => p(d)); });
  if (S.sort) {
    const { key, up } = S.sort;
    rows = [...rows].sort((a, b) => {
      const x = decorate(t, a)[key], y = decorate(t, b)[key];
      if (x === undefined) return 1;
      if (y === undefined) return -1;
      const c = typeof x === "number" && typeof y === "number" ? x - y : String(fmt(x)).localeCompare(fmt(y));
      return up ? -c : c;
    });
  }
  return rows;
}

function renderGrid() {
  const t = cur();
  if (!t) return;
  const cols = ["id", ...(classed(t) ? ["class"] : []), ...orderKeys(Object.keys(t.doc.fields))];
  const rows = visibleRows(t);
  const badIds = new Set(S.errors.map((e) => (e.match(/(?:^|\s)([\w-]+)\.[\w]+:/) || [])[1]).filter(Boolean));
  const th = cols.map((c) => el("th", {
    class: S.sort && S.sort.key === c ? `sorted${S.sort.up ? " up" : ""}` : "",
    title: t.doc.fields[c] ? t.doc.fields[c].type + (t.doc.fields[c].ref ? ` → ${t.doc.fields[c].ref}` : "") : "",
    onclick: () => { S.sort = S.sort && S.sort.key === c ? (S.sort.up ? null : { key: c, up: true }) : { key: c, up: false }; renderGrid(); },
  }, c));
  const body = rows.map((r) => el("tr", {
    class: [r.id === S.sel ? "sel" : "", badIds.has(r.id) ? "bad" : ""].join(" ").trim(),
    onclick: () => go(S.cur, r.id),
  }, cols.map((c) => (c === "class" ? el("td", { class: "cls", title: "from the catalog" }, classOf(r.id) || "·") : cell(r[c])))));
  const count = el("p", { class: "hint", style: "margin:6px 14px" },
    rows.length === t.doc.rows.length ? `${rows.length} rows` : `${rows.length} of ${t.doc.rows.length} rows`,
    S.sort ? " · sorted for viewing; the file keeps its order" : "");
  $("#grid").replaceChildren(el("table", {}, el("thead", {}, el("tr", {}, th)), el("tbody", {}, body)), count);
}

function cell(v) {
  if (v === undefined) return el("td", { class: "none" }, "·");
  if (typeof v === "number") return el("td", { class: "num" }, String(v));
  if (typeof v === "string" && /^#[0-9a-f]{6}$/i.test(v)) return el("td", {}, swatch(v), v);
  if (typeof v === "object") return el("td", { class: "obj", title: JSON.stringify(v, null, 1) }, JSON.stringify(v));
  return el("td", {}, fmt(v));
}

function renderViewBody() {
  const box = $("#grid");
  box.replaceChildren();
  add(box, el("div", { class: "view" }, VIEWS[S.view](S.filter.trim().toLowerCase())));
}

// ------------------------------------------------------------------- views --

function recipeLine(r) {
  return el("div", { class: "line" },
    outputs(r).map((o, i) => [i ? ", " : "", el("a", { class: "go", onclick: () => openItem(o.id) }, itemName(o.id)), o.n > 1 ? ` ×${o.n}` : ""]),
    el("span", { class: "arrow" }, "  ←  "), chips(r.cost),
    r.tool ? el("span", { class: "chip tag" }, `needs ${itemName(r.tool)}`) : "",
    r.station && r.bench ? el("span", { class: "chip tag" }, `and bench ${r.bench}`) : "",
    el("a", { class: "go small", title: "Open the recipe", onclick: () => go("RECIPES", r.id, true) }, " recipe"));
}

function viewWorkbenches(q) {
  const R = listRows("RECIPES").filter((r) => hit(q, r, outputs(r).map((o) => itemName(o.id))));
  const wb = rowById("STRUCTURES", "workbench");
  const cols = [
    ["By hand", "No bench — always available.", R.filter((r) => !r.station && r.bench === 0)],
    ["By hand, carrying a Stone Hammer", "Recipes flagged hammer: bench-1 work you could do on a flat rock. Never a gun.", R.filter((r) => !r.station && r.hammer)],
    ["Workbench", wb ? ["Build a ", link("STRUCTURES", "workbench", "Workbench"), ": ", chips(wb.cost), " Also does everything by hand."] : "",
      R.filter((r) => !r.station && r.bench === 1)],
    ["Workbench II", ["Upgrade the Workbench: ", chips(S.consts.BENCH_UPGRADE_COST), " Also does everything below it."],
      R.filter((r) => !r.station && r.bench === 2)],
    ...stationList().map((s) => [s.name, ["Build a ", link("STRUCTURES", s.row.id, s.name), ": ", chips(s.row.cost),
      " A separate station, not a Workbench tier."], R.filter((r) => r.station === s.id)]),
  ];
  return [
    el("p", { class: "hint" }, "Where everything is made today, straight from RECIPES. A recipe shows once, at the lowest place that makes it; a higher bench does everything below it."),
    el("div", { class: "benches" }, cols.map(([title, sub, list]) => el("div", { class: "card bench" },
      el("h3", {}, `${title} · ${list.length}`), el("div", { class: "hint" }, sub), list.map(recipeLine)))),
    S.tables.CATALOG ? plannedBenches(q) : "",
  ];
}

function plannedBenches(q) {
  const C = listRows("CATALOG");
  const today = (id) => {
    const r = recipesMaking(id)[0];
    return r ? placeLabel(r) : null;
  };
  const recycler = catalogRow("recycler");
  const recyclable = C.filter((c) => c.breaks_down_into);
  return el("div", {},
    el("h3", { class: "section" }, "Planned bench split — from Notion's Workbenches table"),
    el("p", { class: "hint" }, "Where the benches are heading. None of these exists in the game yet; each item's “today” tag is where it is actually made now."),
    el("div", { class: "benches" },
      PLANNED_BENCHES.map(([plan, rowId]) => {
        const items = C.filter((c) => c.bench_plan === plan && hit(q, c));
        const bc = rowId ? catalogRow(rowId) : null;
        return el("div", { class: "card bench planned" },
          el("h3", {}, `${plan} · ${items.length}`),
          bc ? el("div", {}, badge(bc.status), " ", link("CATALOG", rowId, bc.name)) : el("div", { class: "hint" }, "bench 0 — the player menu"),
          bc && bc.notes ? el("div", { class: "hint prose clamp" }, bc.notes) : "",
          items.map((c) => el("div", { class: "line" },
            el("a", { class: "go", onclick: () => openItem(c.id) }, c.name), " ", badge(c.status),
            today(c.id) ? el("span", { class: "chip tag" }, `today: ${today(c.id)}`) : "")));
      }),
      recycler ? el("div", { class: "card bench planned" },
        el("h3", {}, `Recycler · ${recyclable.length} items`),
        el("div", {}, badge(recycler.status), " ", link("CATALOG", "recycler", recycler.name)),
        recycler.notes ? el("div", { class: "hint prose clamp" }, recycler.notes) : "",
        recyclable.filter((c) => hit(q, c)).map((c) => el("div", { class: "line" },
          el("a", { class: "go", onclick: () => openItem(c.id) }, c.name), el("span", { class: "hint" }, ` → ${c.breaks_down_into}`)))) : ""));
}

function viewWeapons(q) {
  const C = listRows("CATALOG").filter((c) => c.category === "Weapons");
  const filed = new Set(C.map((c) => c.id));
  const loose = listRows("WEAPONS").filter((w) => !filed.has(w.id)).map((w) => ({ id: w.id, name: w.name, status: "in game" }));
  const table = (list) => el("table", { class: "vt" },
    el("thead", {}, el("tr", {}, ["Name", "status", "dmg", "cd", "reach / mag", "stagger · bleed", "uses", "crafted at", "found in", "design ratings"].map((h) => el("th", {}, h)))),
    el("tbody", {}, list.map((c) => {
      const w = rowById("WEAPONS", c.id);
      const made = w ? recipesMaking(c.id) : [];
      const found = w ? foundSpots(c.id).length : 0;
      return el("tr", { class: S.sel === c.id ? "sel" : "", onclick: () => openItem(c.id) },
        el("td", {}, swatch(w && w.color), c.name), el("td", {}, badge(c.status)),
        el("td", { class: "num" }, w ? w.dmg : ""), el("td", { class: "num" }, w ? w.cd : ""),
        el("td", { class: "num" }, w ? (w.kind === "gun" ? `mag ${w.mag}` : w.range) : ""),
        el("td", {}, w ? [w.stagger ? `stagger ${w.stagger}s` : "", w.bleed ? `bleed ${w.bleed}/s` : ""].filter(Boolean).join(" · ") : ""),
        el("td", { class: "num" }, w ? (w.dur ?? "∞") : ""),
        el("td", {}, w ? (made.length ? [...new Set(made.map(placeLabel))].join(", ") : "found only") : c.bench_plan ? `planned: ${c.bench_plan}` : ""),
        el("td", {}, w ? (found ? `${found} place${found === 1 ? "" : "s"}` : none()) : ""),
        el("td", { class: "small" }, c.ratings ? Object.entries(c.ratings).map(([k, v]) => `${k.replace(/_/g, " ")} ${v}`).join(" · ") : ""));
    })));
  const section = (title, subs) => [el("h2", { class: "group" }, title), subs.map((sub) => {
    const list = C.filter((c) => c.subcategory === sub && hit(q, c, rowById("WEAPONS", c.id)));
    if (!list.length) return "";
    const live = list.filter((c) => c.status === "in game").length;
    return [el("h3", { class: "section" }, `${sub} · ${live} in game, ${list.length - live} planned`), table(list)];
  })];
  const other = C.filter((c) => !MELEE.includes(c.subcategory) && !RANGED.includes(c.subcategory) && hit(q, c));
  return [
    el("p", { class: "hint" }, "Weapons by class — Notion's six melee classes, then its eight ranged ones — with the game's numbers beside each weapon that exists and the design ratings for the ones that don't yet. The class lives in the catalog: change it there."),
    section("Melee", MELEE), section("Ranged", RANGED),
    other.length ? [el("h3", { class: "section" }, "Other classes"), table(other)] : "",
    loose.length ? [el("h3", { class: "section" }, "In the game but not in the catalog"), table(loose.filter((c) => hit(q, c)))] : "",
  ];
}

// ------------------------------------------------------- finding and odds --

// Loot.roll_container: a search makes a whole number of rolls between the
// container's two `rolls` values, each a weighted pick with replacement. So
// the chance of at least one of an entry is 1 − (1 − p)^r, averaged over r.
// Base odds: Luck and the loot perks are on top of this.
function searchChance(p, rolls) {
  const [lo, hi] = Array.isArray(rolls) ? rolls : [1, 1];
  let s = 0;
  for (let r = lo; r <= hi; r++) s += 1 - Math.pow(1 - p, r);
  return s / (hi - lo + 1);
}
const pct = (x) => `${(x * 100).toFixed(x < 0.1 ? 1 : 0)}%`;
// A body that carries a named table rolls it twice (Loot._roll_enemy_drop).
const BODY_ROLLS = [2, 2];
const bodiesRolling = (table) => listRows("ENEMIES").filter((e) => e.loot_table === table);
// A loot entry's item id: `weapon:pistol` → pistol, `scrap` → scrap. Keys
// are per-car and not items.
function entryItem(entry) {
  const m = String(entry).match(/^(weapon|gear|armor|item|key):(.*)$/);
  return m ? (m[1] === "key" ? null : m[2]) : String(entry);
}

// Every container and body an item can come out of, best odds first — the
// loot tables, and the brain matter a kill drops (BRAIN_DROPS, where `also`
// comes with the main drop, so it has the same chance).
function foundSpots(id) {
  const out = [];
  for (const s of lootSources(lootId(id))) {
    for (const c of s.containers) out.push({ chance: searchChance(s.share, c.rolls), per: "search", table: s.table, e: s.e, where: link("CONTAINERS", c.id, c.label || c.id), name: c.label || c.id });
    for (const b of bodiesRolling(s.table)) out.push({ chance: searchChance(s.share, BODY_ROLLS), per: "kill", table: s.table, e: s.e, where: link("ENEMIES", b.id, `${b.name || b.id} body`), name: `${b.name || b.id} body` });
  }
  for (const [enemy, d] of Object.entries(S.consts.BRAIN_DROPS || {})) {
    const hitDrop = d.id === id ? d : d.also && d.also.id === id ? d.also : null;
    if (!hitDrop) continue;
    const name = `${(rowById("ENEMIES", enemy) || {}).name || enemy} body`;
    out.push({ chance: d.chance, per: "kill", table: null, e: hitDrop, where: link("ENEMIES", enemy, name), name });
  }
  return out.sort((a, b) => b.chance - a.chance);
}

// What a loot table can give, with per-roll and (given rolls) per-search odds.
function tableContents(tableName, rolls, perWhat) {
  const lt = rowById("LOOT", tableName);
  const entries = lt && Array.isArray(lt.entries) ? lt.entries : [];
  const total = entries.reduce((a, e) => a + (e.w || 0), 0);
  const rows = entries.map((e) => ({ e, p: total ? e.w / total : 0 })).sort((a, b) => b.p - a.p);
  if (!rows.length) return el("p", { class: "hint" }, `No loot table called ${tableName}.`);
  return el("table", { class: "vt" },
    el("thead", {}, el("tr", {}, ["Item", "at a time", "per roll", perWhat].filter(Boolean).map((h) => el("th", {}, h)))),
    el("tbody", {}, rows.map(({ e, p }) => {
      const id = entryItem(e.id);
      return el("tr", { class: S.sel === id ? "sel" : "", onclick: () => id && openItem(id) },
        el("td", {}, id ? [swatch((findItem(id) || { row: {} }).row.color), itemName(id)] : e.id),
        el("td", { class: "num" }, e.min === e.max ? String(e.min) : `${e.min}–${e.max}`),
        el("td", { class: "num" }, pct(p)),
        perWhat ? el("td", { class: "num" }, el("b", {}, pct(searchChance(p, rolls)))) : "");
    })));
}

function containerCard(c) {
  const F = S.consts.FURNISHING || {};
  const stands = Object.entries(F).map(([b, list]) => {
    const total = list.reduce((a, x) => a + x[1], 0);
    const w = list.filter((x) => x[0] === c.id).reduce((a, x) => a + x[1], 0);
    return w ? `${b} (${pct(w / total)} of its furniture)` : null;
  }).filter(Boolean);
  return el("div", {},
    el("h3", {}, "Can contain"),
    el("p", { class: "hint" }, "A search rolls ", link("LOOT", c.table, `table ${c.table}`), ` ${c.rolls[0]}–${c.rolls[1]} times. `,
      "“Per search” is the chance of at least one, at base odds."),
    tableContents(c.table, c.rolls, "per search"),
    el("h3", {}, "Stands in"),
    stands.length ? el("p", {}, stands.join(" · ")) : el("p", { class: "hint" }, "No building's furnishing table places it; the world generator puts it where it stands."));
}

function lootTableCard(lt) {
  const conts = listRows("CONTAINERS").filter((c) => c.table === lt.id);
  const bodies = bodiesRolling(lt.id);
  return el("div", {},
    el("h3", {}, "Rolled by"),
    conts.length || bodies.length ? el("ul", { class: "refs" },
      conts.map((c) => el("li", {}, link("CONTAINERS", c.id, c.label || c.id), el("span", { class: "hint" }, ` · ${c.rolls[0]}–${c.rolls[1]} rolls a search`))),
      bodies.map((b) => el("li", {}, link("ENEMIES", b.id, `${b.name || b.id} body`), el("span", { class: "hint" }, " · 2 rolls a kill"))))
      : el("p", { class: "hint" }, "Nothing rolls this table."),
    el("h3", {}, "Contents"), tableContents(lt.id, null, null));
}

function enemyCard(e) {
  // What the body gives up besides a loot table: its BRAIN_DROPS row, one
  // roll a kill however many loot perks are stacked on top.
  const d = (S.consts.BRAIN_DROPS || {})[e.id];
  return el("div", {},
    d ? [el("h3", {}, "Brain matter"), el("div", { class: "line" },
      el("b", {}, pct(d.chance)), " a kill: ", el("a", { class: "go", onclick: () => openItem(d.id) }, itemName(d.id)), ` ${d.min}–${d.max}`,
      d.also ? [" and ", el("a", { class: "go", onclick: () => openItem(d.also.id) }, itemName(d.also.id)), ` ${d.also.min}–${d.also.max}`] : "",
      el("span", { class: "hint" }, " (BRAIN_DROPS)"))] : "",
    e.loot_table ? [el("h3", {}, "Carries"), el("p", { class: "hint" }, "Its body rolls ", link("LOOT", e.loot_table, `table ${e.loot_table}`), " twice."),
      tableContents(e.loot_table, BODY_ROLLS, "per kill")] : "");
}

// The three questions about any item, answered first: where do I make it,
// where do I find it, what is it for.
function itemSummary(id) {
  const made = recipesMaking(id);
  const used = [...recipesUsing(id), ...structuresUsing(id)];
  const spots = foundSpots(id);
  const harvest = rowsOf(S.consts.HARVEST || {}).filter((h) => h.res === id || h.bonus === id);
  return el("div", { class: "card summary" },
    el("div", {}, el("b", {}, "Crafted at: "), made.length ? made.map((r, i) => [i ? " · " : "",
      link("RECIPES", r.id, placeLabel(r)), r.station && r.bench ? ` + bench ${r.bench}` : "", r.hammer ? " (or by hand, carrying a Stone Hammer)" : ""])
      : el("span", { class: "hint" }, "can't be crafted")),
    el("div", {}, el("b", {}, "Found in: "), spots.length
      ? [spots.slice(0, 4).map((s, i) => [i ? ", " : "", s.where, ` ${pct(s.chance)}`]), spots.length > 4 ? ` and ${spots.length - 4} more below` : ""]
      : el("span", { class: "hint" }, "no container or body")),
    harvest.length ? el("div", {}, el("b", {}, "Harvested from: "), harvest.map((h) => h.id).join(", ")) : "",
    el("div", {}, el("b", {}, "Used in: "), used.length ? `${used.length} recipe${used.length === 1 ? "" : "s"}` : el("span", { class: "hint" }, "nothing")));
}

// ------------------------------------------------------------------- art --

async function toPng(file) {
  if (file.type === "image/png") return file;
  const bmp = await createImageBitmap(file);
  const c = document.createElement("canvas");
  c.width = bmp.width;
  c.height = bmp.height;
  c.getContext("2d").drawImage(bmp, 0, 0);
  return new Promise((res) => c.toBlob(res, "image/png"));
}

async function uploadArt(name, file) {
  let png;
  try { png = await toPng(file); } catch { return toast(`${file.name} is not an image the browser can read.`, true); }
  const r = await fetch(`/api/art/${name}.png`, { method: "PUT", headers: { "Content-Type": "image/png", "X-Edit-Token": TOKEN }, body: png });
  const text = await r.text();
  let j;
  try { j = JSON.parse(text); } catch { j = { errors: [text] }; }
  if (!r.ok) return toast(`Not saved: ${(j.errors || [text]).join("; ")}`, true);
  S.artVer = Date.now();
  toast(`Saved ${j.file} (${j.width}×${j.height}). The game uses it now; commit it with git.`);
  await load();
}

async function removeArt(name) {
  if (!confirm(`Delete art/items/${name}.png? The item goes back to its placeholder.`)) return;
  const r = await fetch(`/api/art/${name}.png`, { method: "DELETE", headers: { "X-Edit-Token": TOKEN } });
  if (!r.ok) return toast(`Not removed: ${await r.text()}`, true);
  S.artVer = Date.now();
  toast(`Removed art/items/${name}.png.`);
  await load();
}

function materialTable(ids, q) {
  const H = rowsOf(S.consts.HARVEST || {});
  const rows = ids.filter((id) => hit(q, id, itemName(id)));
  if (!rows.length) return el("p", { class: "hint" }, "Nothing matches.");
  return el("table", { class: "vt" },
    el("thead", {}, el("tr", {}, ["Name", "id", "stack", "wt", "Harvested", "Found in", "Made at", "Used by"].map((h) => el("th", {}, h)))),
    el("tbody", {}, rows.map((id) => {
      const it = findItem(id);
      const r = it ? it.row : {};
      const harvest = H.filter((h) => h.res === id || h.bonus === id).map((h) => h.id);
      const loot = lootSources(lootId(id));
      const made = recipesMaking(id);
      const used = [...recipesUsing(id), ...structuresUsing(id)];
      return el("tr", { class: S.sel === id ? "sel" : "", onclick: () => openItem(id) },
        el("td", {}, swatch(r.color), itemName(id)),
        el("td", { class: "mono" }, id),
        el("td", { class: "num" }, r.stack ?? ""),
        el("td", { class: "num" }, r.wt ?? ""),
        el("td", {}, harvest.length ? harvest.join(", ") : none()),
        el("td", { title: loot.map((s) => s.table).join(", ") }, loot.length ? `${loot.length} loot table${loot.length > 1 ? "s" : ""}` : none()),
        el("td", {}, made.length ? [...new Set(made.map(placeLabel))].join(", ") : none()),
        el("td", { title: used.map((u) => u.name || u.id).join(", ") }, used.length ? `${used.length} recipe${used.length > 1 ? "s" : ""}` : none()));
    })));
}

function viewMaterials(q) {
  const ammo = new Set(S.consts.AMMO_IDS || []);
  const C = listRows("CATALOG");
  const filed = new Set(C.map((c) => c.id));
  const cat = C.filter((c) => c.category === "Materials");
  const unfiled = listRows("RES").filter((r) => !filed.has(r.id) && !ammo.has(r.id)).map((r) => r.id);
  const out = [el("p", { class: "hint" }, "Every base material — the catalog's Materials by subcategory — with where it comes from and what it goes into. Hover a count for the list.")];
  for (const [g, rows] of groupBy(cat, (c) => c.subcategory || "Other")) out.push(el("h3", { class: "section" }, g), materialTable(rows.map((c) => c.id), q));
  if (unfiled.length) out.push(el("h3", { class: "section" }, "Resources not in the catalog yet"), materialTable(unfiled, q));
  return out;
}

function viewTools(q) {
  const H = rowsOf(S.consts.HARVEST || {});
  const opens = (w) => {
    const out = [];
    for (const f of ["axe", "pick", "scythe", "knife", "hammer"]) {
      if (!w[f]) continue;
      for (const h of H) {
        if (h.needs === f) out.push(`needed for ${String(h.label || h.id).toLowerCase()} (${h.id})`);
        else if (h.boost === f) out.push(`faster ${String(h.label || h.id).toLowerCase()} (${h.id})`);
      }
      if (f === "hammer") out.push(`bench-1 work by hand (${listRows("RECIPES").filter((r) => r.hammer).length} recipes)`);
    }
    for (const r of listRows("RECIPES").filter((r) => r.tool === w.id)) out.push(`needed to craft ${r.name}`);
    return out;
  };
  const tools = listRows("WEAPONS").filter((w) => w.tool && hit(q, w));
  const lightIds = [...new Set([
    ...listRows("CATALOG").filter((c) => c.category === "Tools").map((c) => c.id),
    ...listRows("GEAR").filter((g) => g.light).map((g) => g.id),
  ])].filter((id) => hit(q, id, itemName(id)));
  const madeAt = (id) => { const m = recipesMaking(id); return m.length ? [...new Set(m.map(placeLabel))].join(", ") : "found only"; };
  return [
    el("p", { class: "hint" }, "Harvest tools are weapons with a tool flag: what each flag opens comes from HARVEST and RECIPES. Lights are the catalog's Tools."),
    el("h3", { class: "section" }, "Harvest tools"),
    el("table", { class: "vt" },
      el("thead", {}, el("tr", {}, ["Name", "opens", "chop ×", "tool ×", "uses", "made at"].map((h) => el("th", {}, h)))),
      el("tbody", {}, tools.map((w) => el("tr", { class: S.sel === w.id ? "sel" : "", onclick: () => openItem(w.id) },
        el("td", {}, swatch(w.color), w.name),
        el("td", {}, opens(w).map((o) => el("div", {}, o))),
        el("td", { class: "num" }, w.chop_mul ?? ""), el("td", { class: "num" }, w.tool_mul ?? ""),
        el("td", { class: "num" }, w.dur ?? "∞"), el("td", {}, madeAt(w.id)))))),
    el("h3", { class: "section" }, "Lights and other tools"),
    el("table", { class: "vt" },
      el("thead", {}, el("tr", {}, ["Name", "slot", "light", "burns (s)", "made at"].map((h) => el("th", {}, h)))),
      el("tbody", {}, lightIds.map((id) => {
        const g = (findItem(id) || { row: {} }).row;
        return el("tr", { class: S.sel === id ? "sel" : "", onclick: () => openItem(id) },
          el("td", {}, swatch(g.color), itemName(id)), el("td", {}, g.slot ?? ""),
          el("td", { class: "obj" }, g.light !== undefined ? fmt(g.light) : ""), el("td", { class: "num" }, g.burn ?? ""),
          el("td", {}, findItem(id) ? madeAt(id) : badge((catalogRow(id) || {}).status)));
      }))),
  ];
}

function viewAmmo(q) {
  const ids = (S.consts.AMMO_IDS || []).filter((id) => hit(q, id, itemName(id)));
  return [
    el("p", { class: "hint" }, "AMMO_IDS: what Gunsmith multiplies. Each with the guns that eat it, where it is made and where it is found."),
    el("div", { class: "benches" }, ids.map((id) => {
      const r = (findItem(id) || { row: {} }).row;
      const guns = listRows("WEAPONS").filter((w) => w.ammo === id);
      const loot = lootSources(id).sort((a, b) => b.share - a.share);
      return el("div", { class: "card bench" },
        el("h3", {}, swatch(r.color), el("a", { class: "go", onclick: () => openItem(id) }, itemName(id)), el("code", { class: "hint" }, ` ${id}`)),
        el("div", { class: "hint" }, `stack ${r.stack ?? "?"} · weight ${r.wt ?? "?"} each`),
        el("div", { class: "line" }, el("b", {}, "Fired by: "), guns.length ? guns.map((w, i) => [i ? ", " : "", el("a", { class: "go", onclick: () => openItem(w.id) }, w.name), ` (mag ${w.mag})`]) : none()),
        el("div", { class: "line" }, el("b", {}, "Made: "), recipesMaking(id).length ? recipesMaking(id).map((m) => el("div", {},
          `×${outputs(m).find((o) => o.id === id).n} at ${placeLabel(m)} ← `, chips(m.cost))) : none()),
        el("div", { class: "line" }, el("b", {}, `Found in ${loot.length} loot table${loot.length === 1 ? "" : "s"}: `),
          loot.slice(0, 6).map((s, i) => [i ? ", " : "", link("LOOT", s.table, s.table), ` ${(s.share * 100).toFixed(0)}%`]), loot.length > 6 ? " …" : ""));
    })),
  ];
}

function viewCatalog(q) {
  const C = listRows("CATALOG").filter((c) => hit(q, c));
  if (!S.tables.CATALOG) return el("p", { class: "hint" }, "No data/catalog.json yet.");
  const cats = [...groupBy(C, (c) => c.category || "Uncategorised")].sort((a, b) => {
    const i = (k) => (CATEGORY_ORDER.indexOf(k) + 1 || 99);
    return i(a[0]) - i(b[0]);
  });
  const stat = groupBy(listRows("CATALOG"), (c) => c.status);
  return [
    el("p", { class: "hint" }, `Every item, in the game or not: ${[...stat].map(([s, l]) => `${l.length} ${s}`).join(" · ")}. Click one to edit it; the ratings are design intent, 1–5, and the game does not read them.`),
    cats.map(([cat, list]) => [
      el("h3", { class: "section" }, `${cat} · ${list.length}`),
      el("table", { class: "vt" },
        el("thead", {}, el("tr", {}, ["Name", "subcategory", "status", "in code", "made at today", "planned bench", "ratings"].map((h) => el("th", {}, h)))),
        el("tbody", {}, list.map((c) => {
          const f = findItem(c.id);
          const m = f ? recipesMaking(c.id) : [];
          return el("tr", { class: S.sel === c.id ? "sel" : "", onclick: () => openItem(c.id) },
            el("td", {}, c.name), el("td", {}, c.subcategory || ""), el("td", {}, badge(c.status)),
            el("td", {}, f ? el("code", {}, `${f.table}`) : none()),
            el("td", {}, m.length ? [...new Set(m.map(placeLabel))].join(", ") : f ? el("span", { class: "hint" }, "found only") : none()),
            el("td", {}, c.bench_plan || ""),
            el("td", { class: "mono small" }, c.ratings ? Object.entries(c.ratings).map(([k, v]) => `${k.replace(/_/g, " ")} ${v}`).join(" · ") : ""));
        })))]),
  ];
}

// ------------------------------------------------------------------ detail --

function renderDetail() {
  const box = $("#detail");
  box.replaceChildren();
  const t = cur();
  if (!t) return;
  if (t.editable && !S.view) add(box, tableNotes(t));
  const row = S.sel != null ? rowById(S.cur, S.sel) : null;
  if (!row) {
    add(box, el("p", { class: "hint" }, S.view ? "Pick anything in the view to see it here, and edit it if its table is a data file."
      : t.editable ? "Pick a row to edit it. Every save is checked against the whole game — types, and every reference in and out."
        : "Pick a row to see it and what refers to it. This table is still a literal in config.gd, so it is read-only here."));
    return;
  }
  add(box, el("header", {}, el("h2", {}, row.name || row.label || row.id), el("code", {}, `${S.cur} › ${row.id}`),
    !t.editable ? el("span", { class: "chip tag" }, "read-only") : ""));
  if (t.editable) add(box, rowTools(t, row), fieldsForm(t, row), rowNotes(t, row));
  else add(box, readOnlyView(row));
  add(box, xref(t, row));
  markFieldErrors();
}

function tableNotes(t) {
  const d = el("details", { class: "tnotes", open: tableNotes.open ? true : false,
    ontoggle: (e) => (tableNotes.open = e.target.open) },
    el("summary", {}, `Design notes for ${t.name}`));
  add(d, el("textarea", { value: t.doc.notes || "", placeholder: "Why this table is shaped the way it is.",
    oninput: (e) => { t.doc.notes = e.target.value; changed(); } }));
  return d;
}

function rowTools(t, row) {
  const idBox = el("input", { value: row.id, title: "The id is what everything else points at", spellcheck: "false",
    onchange: (e) => renameRow(t, row, e.target.value.trim(), e.target) });
  return el("div", { class: "tools" },
    el("label", { class: "hint" }, "id "), idBox,
    el("button", { onclick: () => dupRow(t, row) }, "Duplicate"),
    el("button", { onclick: () => moveRow(t, row, -1), title: "Row order is data: the game iterates in it" }, "↑"),
    el("button", { onclick: () => moveRow(t, row, 1) }, "↓"),
    el("button", { class: "danger", onclick: () => deleteRow(t, row) }, "Delete"));
}

function fieldsForm(t, row) {
  const fields = t.doc.fields;
  const keys = orderKeys(Object.keys(fields));
  const present = keys.filter((k) => k in row && k !== "notes");
  const absent = keys.filter((k) => !(k in row));
  const form = el("div", { id: "fields" }, el("h3", {}, "Fields"), present.map((k) => fieldRow(t, row, k, fields[k])));
  if (absent.length) {
    const pick = el("select", {}, el("option", { value: "" }, `add a field (${absent.length} unused)…`),
      absent.map((k) => el("option", { value: k }, `${k} — ${fields[k].type}`)));
    pick.addEventListener("change", () => {
      if (!pick.value) return;
      const spec = fields[pick.value];
      row[pick.value] = spec.one_of ? spec.one_of[0] : blank(spec.type);
      changed();
      renderDetail();
    });
    add(form, el("div", { class: "add" }, pick));
  }
  add(form, el("p", { class: "hint" }, "An absent field means what it always meant — no stagger, never wears. × removes one from this row."));
  return form;
}

function blank(type) {
  if (type === "bool") return true;
  if (type === "int" || type === "float") return 0;
  if (type.startsWith("map<")) return {};
  if (type.startsWith("list<")) return [];
  return "";
}

function fieldRow(t, row, key, spec) {
  const wrap = el("div", { class: "field", "data-key": key },
    el("label", { title: key }, key, el("small", {}, spec.type + (spec.ref ? ` → ${spec.ref}` : "") + (spec.key_ref ? ` keys → ${spec.key_ref}` : ""))),
    editor(t, row, key, spec),
    el("button", { class: "x", title: `Remove ${key} from this row`, onclick: () => { delete row[key]; changed(); renderDetail(); } }, "×"));
  add(wrap, el("div", { class: "err", hidden: true }));
  return wrap;
}

function markFieldErrors() {
  const id = S.sel;
  for (const f of document.querySelectorAll("#fields .field")) {
    const key = f.dataset.key;
    const mine = S.errors.filter((e) => new RegExp(`(^|\\s)${esc(id)}\\.${esc(key)}:`).test(e));
    f.classList.toggle("bad", mine.length > 0);
    const box = f.querySelector(".err");
    box.hidden = mine.length === 0;
    box.textContent = mine.map((e) => e.replace(/^.*?:\s*/, "")).join("; ");
  }
}
const esc = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

function editor(t, row, key, spec) {
  const set = (v) => { row[key] = v; changed(); };
  const type = spec.type;
  if (Array.isArray(spec.one_of)) {
    const opts = spec.one_of.includes(row[key]) ? spec.one_of : [row[key], ...spec.one_of];
    return el("select", { onchange: (e) => set(e.target.value) }, opts.map((o) => el("option", { value: o, selected: o === row[key] }, o)));
  }
  if (type === "bool") return el("input", { type: "checkbox", checked: row[key] === true, onchange: (e) => set(e.target.checked) });
  if (type === "int" || type === "float") return numInput(row[key], type, set);
  if (type === "string") {
    // Free text that is really a vocabulary (a subcategory) offers the values
    // already in the column.
    const suggest = spec.ref ? null : [...new Set(t.doc.rows.map((r) => r[key]).filter((v) => typeof v === "string" && v.length < 40))];
    return strInput(row[key], spec.ref, set, suggest);
  }
  const inner = type.slice(type.indexOf("<") + 1, -1);
  if (type.startsWith("map<")) return mapEditor(row[key] || {}, inner, spec.key_ref, spec.ref, set);
  if (type.startsWith("list<")) return listEditor(row[key] || [], inner, spec.ref, set);
  return el("code", {}, JSON.stringify(row[key]));
}

// A number box that keeps what was typed. Anything that is not a number of
// the right kind is sent as typed, and the server names it.
function numInput(v, type, set) {
  const ok = (s) => (type === "int" ? /^-?\d+$/.test(s) : s.trim() !== "" && Number.isFinite(Number(s)));
  return el("input", { type: "text", inputmode: type === "int" ? "numeric" : "decimal", value: v === undefined ? "" : String(v),
    oninput: (e) => {
      const s = e.target.value;
      e.target.classList.toggle("invalid", !ok(s));
      set(ok(s) ? Number(s) : s);
    } });
}

let listSeq = 0;
function datalist(values) {
  if (!values || !values.length) return [null, null];
  const id = `dl${++listSeq}`;
  return [id, el("datalist", { id }, values.map((x) => el("option", { value: x })))];
}

function strInput(v, ref, set, suggest) {
  const [dl, list] = datalist(ref ? setIds(ref) : suggest);
  const input = el("input", { type: "text", value: v ?? "", list: dl, spellcheck: "false", oninput: (e) => { set(e.target.value); syncColor(); } });
  const isColor = typeof v === "string" && /^#[0-9a-f]{6}$/i.test(v);
  if (!isColor) return el("div", { class: "row2" }, input, list);
  const picker = el("input", { type: "color", value: v, oninput: (e) => { input.value = e.target.value; set(e.target.value); } });
  function syncColor() { if (/^#[0-9a-f]{6}$/i.test(input.value)) picker.value = input.value; }
  return el("div", { class: "row2" }, input, picker, list);
}

function mapEditor(obj, inner, keyRef, valRef, set) {
  const box = el("div", {});
  const entries = Object.entries(obj);
  const commit = () => set(Object.fromEntries(entries.filter(([k]) => k !== "")));
  const [dl, list] = datalist(keyRef ? setIds(keyRef) : null);
  entries.forEach((pair, i) => {
    const val = inner === "string" ? strInput(pair[1], valRef, (v) => { pair[1] = v; commit(); })
      : inner === "bool" ? el("input", { type: "checkbox", checked: pair[1], onchange: (e) => { pair[1] = e.target.checked; commit(); } })
        : numInput(pair[1], inner, (v) => { pair[1] = v; commit(); });
    add(box, el("div", { class: "kv" },
      el("input", { type: "text", value: pair[0], list: dl, spellcheck: "false", oninput: (e) => { pair[0] = e.target.value; commit(); } }),
      val,
      el("button", { class: "x", onclick: () => { entries.splice(i, 1); commit(); renderDetail(); } }, "×")));
  });
  add(box, list, el("button", { onclick: () => { entries.push(["", blank(inner)]); commit(); renderDetail(); } }, "+ entry"));
  return box;
}

function listEditor(arr, inner, ref, set) {
  const box = el("div", {});
  const items = [...arr];
  const commit = () => set([...items]);
  items.forEach((v, i) => {
    const input = inner === "string" ? strInput(v, ref, (x) => { items[i] = x; commit(); }) : numInput(v, inner, (x) => { items[i] = x; commit(); });
    add(box, el("div", { class: "row2" }, input, el("button", { class: "x", onclick: () => { items.splice(i, 1); commit(); renderDetail(); } }, "×")));
  });
  add(box, el("button", { onclick: () => { items.push(blank(inner)); commit(); renderDetail(); } }, "+ item"));
  return box;
}

function rowNotes(t, row) {
  return el("div", {}, el("h3", {}, "Notes"),
    el("textarea", { value: row.notes || "", placeholder: "Why this row is the way it is. The game never reads this.",
      oninput: (e) => { if (e.target.value.trim()) row.notes = e.target.value; else delete row.notes; changed(); } }));
}

function readOnlyView(row) {
  return el("div", {}, el("h3", {}, "Fields"), orderKeys(Object.keys(row).filter((k) => k !== "id")).map((k) =>
    el("div", { class: "ro-field" }, el("code", {}, k), el("pre", {}, typeof row[k] === "object" ? JSON.stringify(row[k], null, 1) : fmt(row[k])))));
}

// ------------------------------------------------------------- row actions --

function freshId(t, base) {
  let id = base, n = 2;
  while (t.doc.rows.some((r) => r.id === id)) id = `${base}${n++}`;
  return id;
}

function addRow() {
  const t = cur();
  const id = prompt(`New ${t.name} row — id (what everything else will point at):`, freshId(t, "new"));
  if (!id) return;
  if (t.doc.rows.some((r) => r.id === id)) return toast(`${id} already exists.`, true);
  const row = { id };
  if (t.doc.fields.name) row.name = id;
  t.doc.rows.push(row);
  go(S.cur, id);
  changed();
}

function dupRow(t, row) {
  const id = prompt(`Copy ${row.id} as — new id:`, freshId(t, row.id));
  if (!id) return;
  if (t.doc.rows.some((r) => r.id === id)) return toast(`${id} already exists.`, true);
  const copy = structuredClone(row);
  copy.id = id;
  delete copy.notes;
  t.doc.rows.splice(t.doc.rows.indexOf(row) + 1, 0, copy);
  go(S.cur, id, !!S.view);
  changed();
}

function moveRow(t, row, d) {
  const i = t.doc.rows.indexOf(row), j = i + d;
  if (j < 0 || j >= t.doc.rows.length) return;
  t.doc.rows.splice(i, 1);
  t.doc.rows.splice(j, 0, row);
  changed();
}

function deleteRow(t, row) {
  const refs = referencedBy(t.name, row.id);
  const warn = refs.length ? `\n\n${refs.length} other place(s) name it, and the save will be refused until they don't:\n` +
    refs.slice(0, 8).map((r) => `  ${r.table} ${r.id} · ${r.path}`).join("\n") : "";
  if (!confirm(`Delete ${t.name} ${row.id}?${warn}`)) return;
  t.doc.rows.splice(t.doc.rows.indexOf(row), 1);
  S.sel = null;
  changed();
  renderDetail();
}

function renameRow(t, row, id, input) {
  if (!id || id === row.id) { input.value = row.id; return; }
  if (t.doc.rows.some((r) => r.id === id)) { toast(`${id} already exists.`, true); input.value = row.id; return; }
  const refs = referencedBy(t.name, row.id);
  if (refs.length && !confirm(`${refs.length} other place(s) name ${row.id}. Renaming it breaks them, and the save will be refused until they are updated too. Rename anyway?`)) {
    input.value = row.id;
    return;
  }
  row.id = id;
  go(S.cur, id, !!S.view);
  changed();
}

function addToCatalog(row) {
  const t = S.tables.CATALOG;
  t.doc.rows.push({ id: row.id, name: row.name || row.id, status: "in game" });
  go("CATALOG", row.id, !!S.view);
  changed();
}

// -------------------------------------------------------- cross-references --

// Every place in the content that names this row: a value equal to its id
// (or `weapon:id` and friends, the loot grammar), or a key equal to it inside
// a nested object such as a cost. A row's own top-level keys are its fields,
// not references, so `"axe": true` on a Fire Axe does not count as naming the
// Hatchet. The catalog row with the same id is the same item, not a reference.
function referencedBy(table, id) {
  const want = new Set([id, `weapon:${id}`, `gear:${id}`, `armor:${id}`, `item:${id}`]);
  const out = [];
  const walk = (v, path, depth, hit_) => {
    if (typeof v === "string") { if (want.has(v)) hit_(path); return; }
    if (Array.isArray(v)) { v.forEach((x, i) => walk(x, `${path}[${i}]`, depth + 1, hit_)); return; }
    if (isObj(v)) {
      for (const [k, x] of Object.entries(v)) {
        if (depth === 0 && (k === "id" || k === "name" || k === "notes")) continue;
        if (depth > 0 && k === id) hit_(path ? `${path}.${k}` : k);
        walk(x, path ? `${path}.${k}` : k, depth + 1, hit_);
      }
    }
  };
  for (const name of S.order) {
    if (name === "CATALOG") continue;
    for (const r of listRows(name)) {
      if (name === table && r.id === id) continue;
      walk(r, "", 0, (path) => out.push({ table: name, id: r.id, path }));
    }
  }
  for (const [name, v] of Object.entries(S.consts)) {
    for (const r of rowsOf(v)) walk(r, "", 0, (path) => out.push({ table: name, id: r.id, path, isConst: true }));
  }
  return out;
}

function go(table, id, keepView = false) {
  if (!S.tables[table]) return;
  if (!keepView) S.view = null;
  const switching = table !== S.cur;
  S.cur = table;
  S.sel = id;
  if (switching) {
    // The verdict belongs to the table it was given for.
    S.errors = [];
    if (!S.view) { S.filter = ""; S.sort = null; }
    if (S.tables[table].dirty) validate();
  }
  writeHash();
  render();
}

function goView(v) {
  S.view = v;
  S.filter = "";
  writeHash();
  render();
}

function writeHash() {
  const sel = S.sel ? `${S.cur}/${encodeURIComponent(S.sel)}` : S.cur;
  history.replaceState(null, "", `#${S.view ? `view:${S.view}${S.sel ? `/${sel}` : ""}` : sel}`);
}

function link(table, id, text) {
  if (!S.tables[table]) return el("span", {}, text || `${table} ${id}`);
  return el("a", { class: "go", onclick: () => go(table, id, !!S.view) }, text || `${table} ${id}`);
}

const chips = (obj) => Object.entries(obj || {}).map(([k, n]) => el("span", { class: "chip" }, `${n} ${itemName(k)}`));

function lootSources(entryId) {
  const out = [];
  const conts = listRows("CONTAINERS");
  for (const lt of listRows("LOOT")) {
    const entries = Array.isArray(lt.entries) ? lt.entries : [];
    const total = entries.reduce((a, e) => a + (e.w || 0), 0);
    for (const e of entries) {
      if (e.id === entryId) out.push({ table: lt.id, e, share: total ? e.w / total : 0, containers: conts.filter((c) => c.table === lt.id) });
    }
  }
  return out;
}

// Where an item can be found: every container and body, with the chance of
// at least one per search or per kill, best first.
function lootCards(entryId, empty) {
  const id = entryItem(entryId);
  const spots = foundSpots(id);
  const orphan = lootSources(entryId).filter((s) => !s.containers.length && !bodiesRolling(s.table).length);
  if (!spots.length && !orphan.length) return el("p", { class: "hint" }, empty);
  return el("div", { class: "card" },
    el("div", { class: "hint" }, "Chance of at least one, at base odds (Luck and the loot perks add to it)."),
    spots.map((s) => el("div", { class: "line" }, s.where, " ", el("b", {}, pct(s.chance)),
      el("span", { class: "hint" }, ` a ${s.per} · ${s.e.min === s.e.max ? s.e.min : `${s.e.min}–${s.e.max}`} at a time · `),
      s.table ? link("LOOT", s.table, `table ${s.table}`) : el("span", { class: "hint" }, "brain drop"))),
    orphan.map((s) => el("div", { class: "line" }, link("LOOT", s.table, `table ${s.table}`), el("span", { class: "hint" }, " — nothing rolls this table"))));
}

function recipeCard(r) {
  const tags = Object.entries(r).filter(([k]) => !RECIPE_KEYS.includes(k)).map(([k, v]) => el("span", { class: "chip tag" }, v === true ? k : `${k}: ${v}`));
  return el("div", { class: "card" },
    link("RECIPES", r.id, r.name || r.id), " — ", el("b", {}, placeLabel(r)), r.station ? "" : el("span", { class: "hint" }, ` (bench ${r.bench})`),
    el("div", {}, chips(r.cost), tags, r.xp ? el("span", { class: "chip tag" }, `${r.xp} xp`) : ""));
}

// How the item looks, and where to change it: upload or drop an image on
// either slot. The icon is the pack and hotbar; the ground sprite is
// optional and falls back to the icon. Without either the game draws the
// placeholder shown here.
function lookCard(table, row) {
  if (![...CLASSED, "CATALOG"].includes(table) || row.id === "fists") return "";
  const id = row.id;
  const has = (n) => S.art.includes(n);
  const item = findItem(id) || { table, row };
  const pip = item.table === "RES" || item.table === "CONSUMABLES";
  const color = item.row.color || "#8b929a";
  const slot = (suffix, caption) => {
    const name = id + suffix;
    const shown = has(name) ? name : suffix && has(id) ? id : null;
    const pick = el("input", { type: "file", accept: "image/png,image/jpeg,image/webp,image/gif", hidden: true,
      onchange: (e) => e.target.files[0] && uploadArt(name, e.target.files[0]) });
    const fig = el("figure", {
      class: "drop", title: "Drop an image here, or use Upload",
      ondragover: (e) => { e.preventDefault(); fig.classList.add("over"); },
      ondragleave: () => fig.classList.remove("over"),
      ondrop: (e) => { e.preventDefault(); fig.classList.remove("over"); const f = e.dataTransfer.files[0]; if (f) uploadArt(name, f); },
    },
    shown ? el("img", { src: `/art/items/${shown}.png?v=${S.artVer}`, alt: shown, class: "art" }) : el("span", { class: pip ? "ph pip" : "ph crate", style: `background:${color}` }),
    el("figcaption", {}, caption, suffix && !has(name) && has(id) ? " (icon)" : ""),
    el("div", { class: "row2 center" },
      el("button", { class: "small", onclick: () => pick.click() }, has(name) ? "Replace" : "Upload"),
      has(name) ? el("button", { class: "small danger", onclick: () => removeArt(name) }, "Remove") : ""),
    pick);
    return fig;
  };
  return el("div", {}, el("h3", {}, "Look"), el("div", { class: "card" },
    el("div", { class: "looks" }, slot("", "icon — pack & hotbar"), slot("_ground", "on the ground")),
    el("div", { class: "hint" },
      has(id) ? "" : `Placeholder until there is art: the game draws a ${pip ? "coloured pip" : "coloured crate"} in this row's colour. `,
      "Upload or drop a PNG (JPG and WebP are converted). It is saved as ", el("code", {}, `art/items/${id}.png`),
      " and the game uses it straight away; commit it with git like any other change.")));
}

function catalogCard(table, row) {
  if (!S.tables.CATALOG || !ITEM_TABLES.includes(table) || row.id === "fists" && !catalogRow("fists")) return "";
  const c = catalogRow(row.id);
  if (!c) {
    return el("div", {}, el("h3", {}, "Catalog"), el("div", { class: "card" },
      el("span", { class: "hint" }, "Not in the catalog, so no view files it under a category. "),
      S.tables.CATALOG.editable ? el("button", { onclick: () => addToCatalog(row) }, "Add to catalog") : ""));
  }
  return el("div", {}, el("h3", {}, "Catalog"), el("div", { class: "card" },
    el("b", {}, c.category || "no category"), c.subcategory ? ` › ${c.subcategory}` : "", " ", badge(c.status),
    c.bench_plan ? el("div", {}, "planned bench: ", el("b", {}, c.bench_plan)) : "",
    c.ratings ? el("div", {}, Object.entries(c.ratings).map(([k, v]) =>
      el("span", { class: "chip", title: "design intent, 1–5" }, `${k.replace(/_/g, " ")} ${"●".repeat(v)}${"○".repeat(Math.max(0, 5 - v))}`))) : "",
    c.breaks_down_into ? el("div", { class: "hint" }, "recycles into: ", c.breaks_down_into) : "",
    c.notes ? el("div", { class: "hint prose" }, c.notes) : "",
    el("div", {}, link("CATALOG", c.id, "edit the catalog entry →"))));
}

// A catalog row's way back to the game: the table that defines the item, or
// the fact that nothing does yet.
function catalogBack(row) {
  const f = findItem(row.id);
  return el("div", {}, el("h3", {}, "In the game"), el("div", { class: "card" },
    f ? ["Defined in ", link(f.table, row.id, `${f.table} › ${row.id}`), "."]
      : row.status === "in game" ? el("span", { class: "err-text" }, "Marked in game, but no table has this id.")
        : el("span", { class: "hint" }, "Not built yet. Building it means giving it a row in its real table under this same id.")));
}

function madeAndUsed(id) {
  const made = recipesMaking(id);
  const used = recipesUsing(id);
  const built = structuresUsing(id);
  return [
    el("h3", {}, "Made at"), made.length ? made.map(recipeCard) : el("p", { class: "hint" }, "No recipe makes it."),
    el("h3", {}, `Goes into (${used.length + built.length})`),
    used.length || built.length ? el("ul", { class: "refs" },
      used.map((r) => el("li", {}, link("RECIPES", r.id, r.name), el("span", { class: "hint" }, ` · ${r.cost[id]} at ${placeLabel(r)}`))),
      built.map((s) => el("li", {}, link("STRUCTURES", s.id, s.name), el("span", { class: "hint" }, ` · ${s.cost[id]} to build`)))) : el("p", { class: "hint" }, "Nothing uses it."),
  ];
}

function weaponCard(w) {
  const box = el("div", {});
  const recipes = recipesMaking(w.id);
  add(box, el("h3", {}, "Made at"), recipes.length ? recipes.map(recipeCard)
    : el("p", { class: "hint" }, "No recipe: found, never made — and so mended nowhere (Wear.recipe_for)."));
  add(box, el("h3", {}, "Found in"), lootCards(`weapon:${w.id}`, "No loot table rolls it."));
  if (w.ammo) {
    const res = rowById("RES", w.ammo);
    const makes = recipesMaking(w.ammo);
    add(box, el("h3", {}, `Ammo — ${res ? res.name : w.ammo}`),
      el("p", {}, link("RES", w.ammo, w.ammo), ` · magazine ${w.mag ?? "?"}`, w.pellets > 1 ? ` · ${w.pellets} pellets a shot` : ""),
      makes.map(recipeCard), lootCards(w.ammo, "No loot table rolls this ammo."));
  }
  const wear = S.consts.WEAR || {};
  add(box, el("h3", {}, "Durability"));
  if (!w.dur) {
    add(box, el("p", { class: "hint" }, "No dur: it never wears."));
  } else {
    const share = wear.repair_cost_share ?? 0.5;
    const r = recipes[0];
    let full = null;
    if (r) {
      // Wear.repair_cost at 100% worn: round(cost × share), the main material at least 1.
      full = {};
      let main = null;
      for (const [k, c] of Object.entries(r.cost || {})) {
        if (main === null || c > r.cost[main]) main = k;
        const n = Math.round(c * share);
        if (n > 0) full[k] = n;
      }
      if (main && !full[main]) full[main] = 1;
    }
    add(box, el("div", { class: "card" },
      el("b", {}, `${w.dur} uses`), " — one per connecting swing or shot",
      wear.chop_mul ? `, ${wear.chop_mul}× on scenery` : "", ".",
      el("div", { class: "hint" }, `warns at ${Math.floor(w.dur * (wear.worn_at ?? 0.3))} and ${Math.floor(w.dur * (wear.spent_at ?? 0.1))} uses left`),
      el("div", {}, full ? ["full repair at ", el("b", {}, placeLabel(r)), ": ", chips(full)] : "cannot be repaired: nothing makes it")));
  }
  return box;
}

function xref(t, row) {
  const box = el("section", {});
  const isItem = (CLASSED.includes(t.name) || (t.name === "CATALOG" && findItem(row.id))) && row.id !== "fists";
  if (isItem) add(box, el("h3", {}, "At a glance"), itemSummary(row.id));
  add(box, lookCard(t.name, row), catalogCard(t.name, row));
  if (t.name === "CATALOG") add(box, catalogBack(row));
  if (t.name === "WEAPONS") add(box, weaponCard(row));
  if (t.name === "RES" || t.name === "CONSUMABLES" || t.name === "GEAR") {
    add(box, madeAndUsed(row.id), el("h3", {}, "Found in"), lootCards(lootId(row.id), "No container or body gives it."));
  }
  if (t.name === "CONTAINERS") add(box, containerCard(row));
  if (t.name === "LOOT") add(box, lootTableCard(row));
  if (t.name === "ENEMIES") add(box, enemyCard(row));
  if (t.name !== "CATALOG") {
    const refs = referencedBy(t.name, row.id);
    add(box, el("h3", {}, `Referenced by (${refs.length})`), refs.length
      ? el("ul", { class: "refs" }, refs.map((r) => el("li", {}, r.isConst ? el("span", {}, `${r.table} ${r.id}`) : link(r.table, r.id), " ", el("code", {}, r.path))))
      : el("p", { class: "hint" }, "Nothing else in the content names this row."));
  }
  return box;
}

// -------------------------------------------------------------------- boot --

window.addEventListener("keydown", (e) => {
  if ((e.ctrlKey || e.metaKey) && e.key === "s") { e.preventDefault(); save(); }
});
window.addEventListener("beforeunload", (e) => {
  if (S.order.some((n) => S.tables[n].dirty)) { e.preventDefault(); e.returnValue = ""; }
});

(async () => {
  const hash = decodeURIComponent(location.hash.slice(1));
  const [first, ...rest] = hash.split("/");
  if (first.startsWith("view:")) {
    S.view = first.slice(5) in VIEWS ? first.slice(5) : null;
    [S.cur, S.sel] = [rest[0] || null, rest[1] || null];
  } else if (first) {
    [S.cur, S.sel] = [first, rest[0] || null];
  } else {
    S.view = "Workbenches";
  }
  try {
    await load();
  } catch (err) {
    document.body.replaceChildren(el("p", { style: "padding:20px" }, `Could not reach the editor server: ${err.message}. Is tools\\edit still running?`));
  }
})();
