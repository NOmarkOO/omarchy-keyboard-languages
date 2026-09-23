const assert = require("node:assert/strict")
const fs = require("node:fs")
const Model = require("../KeyboardLayoutModel.js")

const xkb = fs.readFileSync(0, "utf8")
const catalog = Model.parseCatalog(xkb)

assert.ok(catalog.layouts.length > 100)
assert.ok(catalog.shortcuts.some((item) => item.value === "grp:alt_shift_toggle"))
assert.equal(catalog.shortcuts.some((item) => item.value === "grp:switch"), false)
assert.equal(Model.labelFor(catalog, "us", ""), "EN")
assert.equal(Model.labelFor(catalog, "ru", ""), "RU")
assert.equal(Model.labelFor(catalog, "us", "").length, 2)
assert.equal(Model.labelFor(catalog, "us", "", " Work "), "Work")
assert.equal(Model.labelFor(catalog, "us", "", "🇺🇸"), "🇺🇸")
assert.equal(Model.labelFor(catalog, "us", "", ""), "EN")
assert.equal(Model.labelFor(catalog, "us", "", "toolong"), "EN")
assert.equal(Model.normalizeAlias("  pt-BR  "), "pt-BR")
assert.equal(Model.aliasError("pt-BR"), "")
assert.equal(Model.aliasError("🇺🇸ABC"), "")
assert.match(Model.aliasError("1234567"), /6 characters/)
assert.match(Model.aliasError("bad\talias"), /control/)
assert.match(Model.descriptionFor(catalog, "ru", ""), /Russian/)

const configured = [
  { layout: "us", variant: "", latin: true },
  { layout: "ru", variant: "", latin: false }
]
assert.equal(Model.duplicate(configured, "ru", ""), true)
assert.equal(Model.duplicate(configured, "ru", "phonetic"), false)
assert.ok(Model.baseLayoutOptions(catalog, configured).some((item) => item.value === "ru"))
assert.ok(Model.variantOptions(catalog, "ru", configured).some((item) => item.value !== ""))

assert.equal(Model.canDelete(configured, 1).ok, true)
assert.equal(Model.canDelete(configured, 0).ok, false)
assert.match(Model.canDelete(configured, 0).reason, /Latin layout first/)
assert.equal(Model.canDelete([{ layout: "us", variant: "", latin: true }], 0).ok, false)
assert.equal(Model.canDelete([
  { layout: "us", variant: "", latin: true },
  { layout: "by", variant: "latin", latin: true }
], 0).ok, true)
assert.equal(Model.canDelete([
  { layout: "us", variant: "", latin: true },
  { layout: "az", variant: "cyrillic", latin: false }
], 0).ok, false)

assert.equal(Model.isTypedKeyboard("power-button"), false)
assert.equal(Model.isTypedKeyboard("keychron-k2"), true)
assert.equal(Model.selectKeyboard([
  { name: "one", active_layout_index: 0 },
  { name: "two", active_layout_index: 1 }
], "").name, "two")

assert.deepEqual(Model.heroPhrases(), [
  "Switching scripts",
  "Shuffling symbols",
  "Cycling characters",
  "Taming tongues",
  "Wrangling words",
  "Routing runes",
  "Juggling glyphs",
  "Mapping alphabets",
  "Translating taps",
  "Sorting syllables"
])
assert.equal(new Set(Model.heroPhrases()).size, 10)

assert.deepEqual(Model.popupPlacement(100, 30, 300, 40, 800, 600, 220, 12, 4), {
  x: 100, y: 74, width: 300, height: 220, above: false
})
assert.deepEqual(Model.popupPlacement(100, 540, 300, 40, 800, 600, 220, 12, 4), {
  x: 100, y: 316, width: 300, height: 220, above: true
})
assert.deepEqual(Model.popupPlacement(740, 260, 300, 40, 800, 420, 300, 12, 4), {
  x: 488, y: 12, width: 300, height: 244, above: true
})
assert.deepEqual(Model.popupPlacement(-30, 30, 900, 40, 800, 600, 220, 12, 4), {
  x: 12, y: 74, width: 776, height: 220, above: false
})

const state = JSON.parse(fs.readFileSync(require.resolve("./fixtures/state.json"), "utf8"))
assert.deepEqual(Model.normalizeLayouts(state.layouts).map(({ layout, variant }) => ({ layout, variant })), [
  { layout: "us", variant: "" },
  { layout: "ru", variant: "" }
])
assert.deepEqual(Model.normalizeLayouts([
  { layout: "us", variant: "", alias: "Work", latin: true },
  { layout: "us", variant: "dvorak", alias: "DV", latin: true },
  { layout: "ru", variant: "", alias: "1234567", latin: false }
]).map(({ layout, variant, alias }) => ({ layout, variant, alias })), [
  { layout: "us", variant: "", alias: "Work" },
  { layout: "us", variant: "dvorak", alias: "DV" },
  { layout: "ru", variant: "", alias: "" }
])
// Recent-first ("macOS-style") switching.
assert.deepEqual(Model.recentNormalize([2, 2, 9, -1, 0], 3), [2, 0, 1])
assert.deepEqual(Model.recentNormalize(undefined, 3), [0, 1, 2])
assert.deepEqual(Model.recentMoveToFront([0, 1, 2], 2), [2, 0, 1])

let recent = Model.recentNote(Model.recentInitial(), 0, 3)
assert.deepEqual(recent.order, [0, 1, 2])

// A single press goes to the previously used layout; two layouts toggle back and forth.
let press = Model.recentPress(recent, 0, 3)
assert.equal(press.target, 1)
recent = Model.recentCommit(press.state)
assert.deepEqual(recent.order, [1, 0, 2])
press = Model.recentPress(recent, 1, 3)
assert.equal(press.target, 0)
recent = Model.recentCommit(press.state)
assert.deepEqual(recent.order, [0, 1, 2])

// Presses inside one burst walk deeper into the history and wrap around,
// and only the committed burst reorders it.
press = Model.recentPress(recent, 0, 3)
assert.equal(press.target, 1)
press = Model.recentPress(press.state, 1, 3)
assert.equal(press.target, 2)
assert.deepEqual(press.state.order, [0, 1, 2])
press = Model.recentPress(press.state, 2, 3)
assert.equal(press.target, 0)
press = Model.recentPress(press.state, 0, 3)
assert.equal(press.target, 1)
recent = Model.recentCommit(press.state)
assert.deepEqual(recent.order, [1, 0, 2])
assert.equal(recent.base, null)

// Layout changes reported during a burst are its own hops and never rewrite history.
press = Model.recentPress(recent, 1, 3)
assert.equal(press.target, 0)
assert.equal(Model.recentNote(press.state, 0, 3), press.state)
recent = Model.recentCommit(press.state)
assert.deepEqual(recent.order, [0, 1, 2])

// A change made elsewhere (a row click, an XKB shortcut) becomes the most recent layout.
recent = Model.recentNote(recent, 2, 3)
assert.deepEqual(recent.order, [2, 0, 1])
assert.equal(Model.recentPress(recent, 2, 3).target, 0)
assert.equal(Model.recentNote(recent, 7, 3), recent)

// A burst cannot survive the layout count changing under it.
press = Model.recentPress(Model.recentPress(recent, 2, 3).state, 0, 3)
assert.equal(press.target, 1)
press = Model.recentPress(press.state, 1, 2)
assert.equal(press.state.base.length, 2)
assert.ok([0, 1].includes(press.target))
assert.equal(Model.recentCommit(Model.recentInitial()).base, null)
console.log("keyboard-layout model tests passed")
