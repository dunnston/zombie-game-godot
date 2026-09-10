"use strict";
// DEADLINE content editor. Plain JS, no build step, served by
// tools/edit_server.gd. The server is the authority: it validates every save
// and writes the file through DataTable.encode, so nothing here formats JSON
// for disk and nothing here decides whether a save is allowed.

const TOKEN = document.querySelector('meta[name="edit-token"]').content;
const $ = (sel) => document.querySelector(sel);
const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

// Columns and fields that read best first; everything else is alphabetical.
const FIRST = ["name", "label", "kind", "slot", "table", "tier"];
// PROJECT.md §10: 0 is by hand, 1 and 2 the one Workbench and its upgrade.
const BENCH = { 0: "by hand", 1: "Workbench", 2: "upgraded Workbench" };
// The recipe keys the card spells out; any other key shows as a tag.
const RECIPE_KEYS = ["id", "name", "bench", "cost", "give", "xp"];

const S = {
  tables: {},   // name -> {name, editable, file, doc, dirty, gitDirty, loadErrors}
  order: [],
  consts: {},
  problems: [], // broken references across all content, from the server
  cur: null,
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
  for (const kid of kids.flat(Infinity)) {
    if (kid == null || kid === false) continue;
    n.append(kid instanceof Node ? kid : String(kid));
  }
  return n;
}

// DOM append that flattens arrays and skips empty values, the way el() does.
// Plain append() would print "[object HTMLButtonElement]" for an array.
function add(node, ...kids) {
  node.append(...kids.flat(Infinity).filter((k) => k != null && k !== false));
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
  renderHead();
  renderGrid();
}

async function validate() {
  const t = cur();
  if (!t || !t.editable || !t.dirty) return;
  const { j } = await send("POST", `/api/validate/${t.name}`, t);
  S.errors = j.errors || [];
  renderProblems();
  renderHead();
  markFieldErrors();
  renderGrid();
}

async function save() {
  const t = cur();
  if (!t || !t.editable || !t.dirty) return;
  clearTimeout(vTimer);
  const { ok, j } = await send("PUT", `/api/table/${t.name}`, t);
  if (!ok) {
    S.errors = j.errors || [];
    renderProblems();
    renderHead();
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
  renderHead();
  renderProblems();
  renderGrid();
  renderDetail();
}

function renderStatus() {
  const ed = S.order.filter((n) => S.tables[n].editable);
  const git = ed.filter((n) => S.tables[n].gitDirty).map((n) => S.tables[n].file);
  $("#status").replaceChildren(
    `${S.order.length} tables · ${ed.length} editable · the rest still live in config.gd`,
    git.length ? el("span", { class: "warn" }, ` · uncommitted: ${git.join(", ")}`) : "",
  );
}

function renderNav() {
  const mk = (n) => {
    const t = S.tables[n];
    return el("button", { class: n === S.cur ? "cur" : "", onclick: () => go(n, null) },
      el("span", {}, n, t.dirty ? el("span", { class: "dot", title: "Unsaved changes" }, " ●") : ""),
      el("span", { class: t.editable ? "n" : "ro" }, t.editable ? t.doc.rows.length : "read-only"));
  };
  const ed = S.order.filter((n) => S.tables[n].editable);
  const ro = S.order.filter((n) => !S.tables[n].editable);
  const nav = $("#tables");
  nav.replaceChildren();
  add(nav, el("h4", {}, "Data files"), ed.map(mk), el("h4", {}, "Still in config.gd"), ro.map(mk));
}

function renderHead() {
  const t = cur();
  if (!t) return;
  const blocked = S.errors.length > 0;
  const filter = el("input", {
    type: "search", value: S.filter, spellcheck: "false",
    placeholder: "filter: kind=gun ammo=ammoR dmg>30 has:bleed !has:dur rifle",
    oninput: (e) => { S.filter = e.target.value; renderGrid(); },
  });
  $("#head").replaceChildren(
    el("h2", {}, t.name),
    el("span", { class: "file mono" }, t.editable ? t.file : "read-only — migrate it to edit"),
    filter,
    t.editable ? el("button", { onclick: addRow }, "+ Row") : "",
    t.editable ? el("button", { onclick: revert, disabled: !t.dirty }, "Revert") : "",
    t.editable ? el("button", { class: "primary", onclick: save, disabled: !t.dirty || blocked,
      title: blocked ? "Fix the problems listed first" : "Save (Ctrl+S)" }, "Save") : "",
  );
  // Keep the caret in the filter box across re-renders.
  if (document.activeElement && document.activeElement.type === "search") filter.focus();
}

function renderProblems() {
  const t = cur();
  const items = [...(t && t.loadErrors ? t.loadErrors : []), ...S.errors];
  const other = S.problems.filter((p) => !items.includes(p));
  const box = $("#problems");
  box.replaceChildren();
  if (items.length) add(box,el("b", {}, "This change cannot be saved yet:"), el("ul", {}, items.map((e) => el("li", {}, e))));
  if (other.length) add(box,el("b", {}, "Already broken in the content on disk:"), el("ul", {}, other.map((e) => el("li", {}, e))));
}

function visibleRows(t) {
  const preds = parseFilter(S.filter);
  let rows = t.doc.rows.filter((r) => preds.every((p) => p(r)));
  if (S.sort) {
    const { key, up } = S.sort;
    rows = [...rows].sort((a, b) => {
      const x = a[key], y = b[key];
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
  const cols = ["id", ...orderKeys(Object.keys(t.doc.fields))];
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
  }, cols.map((c) => cell(r[c]))));
  const count = el("p", { class: "hint", style: "margin:6px 14px" },
    rows.length === t.doc.rows.length ? `${rows.length} rows` : `${rows.length} of ${t.doc.rows.length} rows`,
    S.sort ? " · sorted for viewing; the file keeps its order" : "");
  $("#grid").replaceChildren(el("table", {}, el("thead", {}, el("tr", {}, th)), el("tbody", {}, body)), count);
}

function cell(v) {
  if (v === undefined) return el("td", { class: "none" }, "·");
  if (typeof v === "number") return el("td", { class: "num" }, String(v));
  if (typeof v === "string" && /^#[0-9a-f]{6}$/i.test(v)) return el("td", {}, el("span", { class: "sw", style: `background:${v}` }), v);
  if (typeof v === "object") return el("td", { class: "obj", title: JSON.stringify(v, null, 1) }, JSON.stringify(v));
  return el("td", {}, fmt(v));
}

// ------------------------------------------------------------------ detail --

function renderDetail() {
  const box = $("#detail");
  box.replaceChildren();
  const t = cur();
  if (!t) return;
  if (t.editable) add(box,tableNotes(t));
  const row = S.sel != null ? rowById(S.cur, S.sel) : null;
  if (!row) {
    add(box,el("p", { class: "hint" }, t.editable
      ? "Pick a row to edit it. Every save is checked against the whole game — types, and every reference in and out."
      : "Pick a row to see it and what refers to it. This table is still a literal in config.gd, so it is read-only here."));
    return;
  }
  add(box,el("header", {}, el("h2", {}, row.name || row.label || row.id), el("code", {}, `${S.cur} › ${row.id}`)));
  if (t.editable) add(box,rowTools(t, row), fieldsForm(t, row), rowNotes(t, row));
  else add(box,readOnlyView(row));
  add(box,xref(t, row));
  markFieldErrors();
}

function tableNotes(t) {
  const d = el("details", { class: "tnotes", open: tableNotes.open ? true : false,
    ontoggle: (e) => (tableNotes.open = e.target.open) },
    el("summary", {}, `Design notes for ${t.name}`));
  d.append(el("textarea", { value: t.doc.notes || "", placeholder: "Why this table is shaped the way it is.",
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
      row[pick.value] = blank(fields[pick.value].type);
      changed();
      renderDetail();
    });
    form.append(el("div", { class: "add" }, pick));
  }
  form.append(el("p", { class: "hint" }, "An absent field means what it always meant — no stagger, never wears. × removes one from this row."));
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
    editor(row, key, spec),
    el("button", { class: "x", title: `Remove ${key} from this row`, onclick: () => { delete row[key]; changed(); renderDetail(); } }, "×"));
  wrap.append(el("div", { class: "err", hidden: true }));
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

function editor(row, key, spec) {
  const set = (v) => { row[key] = v; changed(); };
  const type = spec.type;
  if (type === "bool") return el("input", { type: "checkbox", checked: row[key] === true, onchange: (e) => set(e.target.checked) });
  if (type === "int" || type === "float") return numInput(row[key], type, set);
  if (type === "string") return strInput(row[key], spec.ref, set);
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
function datalist(ref) {
  if (!ref) return [null, null];
  const id = `dl${++listSeq}`;
  return [id, el("datalist", { id }, setIds(ref).map((x) => el("option", { value: x })))];
}

function strInput(v, ref, set) {
  const [dl, list] = datalist(ref);
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
  const [dl, list] = datalist(keyRef);
  entries.forEach((pair, i) => {
    const val = inner === "string" ? strInput(pair[1], valRef, (v) => { pair[1] = v; commit(); })
      : inner === "bool" ? el("input", { type: "checkbox", checked: pair[1], onchange: (e) => { pair[1] = e.target.checked; commit(); } })
      : numInput(pair[1], inner, (v) => { pair[1] = v; commit(); });
    add(box,el("div", { class: "kv" },
      el("input", { type: "text", value: pair[0], list: dl, spellcheck: "false", oninput: (e) => { pair[0] = e.target.value; commit(); } }),
      val,
      el("button", { class: "x", onclick: () => { entries.splice(i, 1); commit(); renderDetail(); } }, "×")));
  });
  add(box,list || "", el("button", { onclick: () => { entries.push(["", blank(inner)]); commit(); renderDetail(); } }, "+ entry"));
  return box;
}

function listEditor(arr, inner, ref, set) {
  const box = el("div", {});
  const items = [...arr];
  const commit = () => set([...items]);
  items.forEach((v, i) => {
    const input = inner === "string" ? strInput(v, ref, (x) => { items[i] = x; commit(); }) : numInput(v, inner, (x) => { items[i] = x; commit(); });
    add(box,el("div", { class: "row2" }, input, el("button", { class: "x", onclick: () => { items.splice(i, 1); commit(); renderDetail(); } }, "×")));
  });
  add(box,el("button", { onclick: () => { items.push(blank(inner)); commit(); renderDetail(); } }, "+ item"));
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
  go(S.cur, id);
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
  go(S.cur, id);
  changed();
}

// -------------------------------------------------------- cross-references --

// Every place in the content that names this row: a value equal to its id
// (or `weapon:id` and friends, the loot grammar), or a key equal to it inside
// a nested object such as a cost. A row's own top-level keys are its fields,
// not references, so `"axe": true` on a Fire Axe does not count as naming the
// Hatchet.
function referencedBy(table, id) {
  const want = new Set([id, `weapon:${id}`, `gear:${id}`, `armor:${id}`, `item:${id}`]);
  const out = [];
  const walk = (v, path, depth, hit) => {
    if (typeof v === "string") { if (want.has(v)) hit(path); return; }
    if (Array.isArray(v)) { v.forEach((x, i) => walk(x, `${path}[${i}]`, depth + 1, hit)); return; }
    if (isObj(v)) {
      for (const [k, x] of Object.entries(v)) {
        if (depth === 0 && (k === "id" || k === "name" || k === "notes")) continue;
        if (depth > 0 && k === id) hit(path ? `${path}.${k}` : k);
        walk(x, path ? `${path}.${k}` : k, depth + 1, hit);
      }
    }
  };
  for (const name of S.order) {
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

function go(table, id) {
  const switching = table !== S.cur;
  S.cur = table;
  S.sel = id;
  if (switching) {
    // The verdict belongs to the table it was given for.
    S.errors = [];
    if (S.tables[table].dirty) validate();
  }
  location.hash = id ? `${table}/${encodeURIComponent(id)}` : table;
  render();
}

function link(table, id, text) {
  if (!S.tables[table]) return el("span", {}, text || `${table} ${id}`);
  return el("a", { class: "go", onclick: () => go(table, id) }, text || `${table} ${id}`);
}

const chips = (obj) => Object.entries(obj || {}).map(([k, n]) => el("span", { class: "chip" }, `${n} ${resName(k)}`));
const resName = (id) => (rowById("RES", id) || {}).name || id;

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

function lootCards(entryId, none) {
  const src = lootSources(entryId);
  if (!src.length) return el("p", { class: "hint" }, none);
  return src.map((s) => el("div", { class: "card" },
    link("LOOT", s.table, `LOOT ${s.table}`), ` — weight ${s.e.w} of the table (${(s.share * 100).toFixed(1)}% a roll), ${s.e.min}–${s.e.max} at a time`,
    s.containers.length ? el("div", { class: "hint" }, "in: ", s.containers.map((c, i) =>
      [i ? ", " : "", link("CONTAINERS", c.id, c.label || c.id), Array.isArray(c.rolls) ? ` (${c.rolls[0]}–${c.rolls[1]} rolls)` : ""])) : ""));
}

function recipeCard(r) {
  const tags = Object.entries(r).filter(([k]) => !RECIPE_KEYS.includes(k)).map(([k, v]) => el("span", { class: "chip tag" }, v === true ? k : `${k}: ${v}`));
  return el("div", { class: "card" },
    link("RECIPES", r.id, r.name || r.id), " — ", el("b", {}, `bench ${r.bench} · ${BENCH[r.bench] || "?"}`),
    el("div", {}, chips(r.cost), tags, r.xp ? el("span", { class: "chip tag" }, `${r.xp} xp`) : ""));
}

function weaponCard(w) {
  const box = el("div", {});
  const recipes = listRows("RECIPES").filter((r) => r.give && r.give.weapon === w.id);
  add(box,el("h3", {}, "Made at"), recipes.length ? recipes.map(recipeCard)
    : el("p", { class: "hint" }, "No recipe: found, never made — and so mended nowhere (Wear.recipe_for)."));
  add(box,el("h3", {}, "Found in"), lootCards(`weapon:${w.id}`, "No loot table rolls it."));
  if (w.ammo) {
    const res = rowById("RES", w.ammo);
    const makes = listRows("RECIPES").filter((r) => r.give && isObj(r.give.res) && w.ammo in r.give.res);
    add(box,el("h3", {}, `Ammo — ${res ? res.name : w.ammo}`),
      el("p", {}, link("RES", w.ammo, w.ammo), ` · magazine ${w.mag ?? "?"}`, w.pellets > 1 ? ` · ${w.pellets} pellets a shot` : ""),
      makes.map(recipeCard), lootCards(w.ammo, "No loot table rolls this ammo."));
  }
  const wear = S.consts.WEAR || {};
  add(box,el("h3", {}, "Durability"));
  if (!w.dur) {
    add(box,el("p", { class: "hint" }, "No dur: it never wears."));
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
    add(box,el("div", { class: "card" },
      el("b", {}, `${w.dur} uses`), " — one per connecting swing or shot",
      wear.chop_mul ? `, ${wear.chop_mul}× on scenery` : "", ".",
      el("div", { class: "hint" }, `warns at ${Math.floor(w.dur * (wear.worn_at ?? 0.3))} and ${Math.floor(w.dur * (wear.spent_at ?? 0.1))} uses left`),
      el("div", {}, full ? ["full repair at ", el("b", {}, `bench ${r.bench}`), ": ", chips(full)] : "cannot be repaired: nothing makes it")));
  }
  return box;
}

function xref(t, row) {
  const box = el("section", {});
  if (t.name === "WEAPONS") add(box,weaponCard(row));
  if (t.name === "RES") {
    add(box,el("h3", {}, "Found in"), lootCards(row.id, "No loot table rolls it."));
  }
  const refs = referencedBy(t.name, row.id);
  add(box,el("h3", {}, `Referenced by (${refs.length})`), refs.length
    ? el("ul", { class: "refs" }, refs.map((r) => el("li", {}, r.isConst ? el("span", {}, `${r.table} ${r.id}`) : link(r.table, r.id), " ", el("code", {}, r.path))))
    : el("p", { class: "hint" }, "Nothing else in the content names this row."));
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
  const [table, id] = decodeURIComponent(location.hash.slice(1)).split("/");
  S.cur = table || null;
  S.sel = id || null;
  try {
    await load();
  } catch (err) {
    document.body.replaceChildren(el("p", { style: "padding:20px" }, `Could not reach the editor server: ${err.message}. Is tools\\edit still running?`));
  }
})();
