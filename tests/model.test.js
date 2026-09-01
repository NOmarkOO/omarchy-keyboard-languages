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
assert.match(Model.descriptionFor(catalog, "ru", ""), /Russian/)

const configured = [
  { layout: "us", variant: "", latin: true },
  { layout: "ru", variant: "", latin: false }
]
assert.equal(Model.duplicate(configured, "ru", ""), true)
assert.equal(Model.duplicate(configured, "ru", "phonetic"), false)
assert.ok(Model.baseLayoutOptions(catalog, configured).some((item) => item.value === "ru"))
assert.ok(Model.variantOptions(catalog, "ru", configured).some((item) => item.value !== ""))

// The default "br" layout is XKB's ABNT2 keymap, but its own description
// ("Portuguese (Brazil)") never says so. Surface the alias in the base-layout
// entry's description so the searchable picker (label/description substring
// match) finds it when someone searches "abnt2".
assert.equal(Model.aliasFor("br"), "ABNT2")
assert.equal(Model.aliasFor("us"), "")
assert.ok(
  Model.baseLayoutOptions(catalog, configured).some(
    (item) => item.value === "br" && item.description.includes("ABNT2")
  )
)
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
console.log("keyboard-layout model tests passed")
