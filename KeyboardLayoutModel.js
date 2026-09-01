// Pure data model for the keyboard-language plugin. It intentionally has no
// Qt dependencies so the same behavior is exercised under Node in tests.

var UNTYPED_KEYBOARDS = /^(hl-virtual-keyboard|power-button|sleep-button|lid-switch|video-bus)/
var HERO_PHRASES = [
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
]

function heroPhrases() {
  return HERO_PHRASES.slice()
}

function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

// Place a popup inside its window, preferring below the trigger and switching
// above when that side provides more room. Kept pure so all four bar
// orientations can be covered without a running shell.
function popupPlacement(triggerX, triggerY, triggerWidth, triggerHeight,
                        windowWidth, windowHeight, desiredHeight, margin, gap) {
  var tx = finiteNumber(triggerX, 0)
  var ty = finiteNumber(triggerY, 0)
  var tw = Math.max(1, finiteNumber(triggerWidth, 1))
  var th = Math.max(0, finiteNumber(triggerHeight, 0))
  var ww = Math.max(1, finiteNumber(windowWidth, 1))
  var wh = Math.max(1, finiteNumber(windowHeight, 1))
  var desired = Math.max(0, finiteNumber(desiredHeight, 0))
  var edge = Math.max(0, finiteNumber(margin, 0))
  var spacing = Math.max(0, finiteNumber(gap, 0))
  var usableWidth = Math.max(1, ww - edge * 2)
  var width = Math.min(tw, usableWidth)
  var belowY = ty + th + spacing
  var aboveBottom = ty - spacing
  var below = Math.max(0, wh - edge - belowY)
  var above = Math.max(0, aboveBottom - edge)
  var opensAbove = below < desired && above > below
  var available = opensAbove ? above : below
  var height = Math.min(desired, available)
  var x = Math.max(edge, Math.min(tx, ww - edge - width))
  var y = opensAbove ? aboveBottom - height : belowY
  y = Math.max(edge, Math.min(y, wh - edge - height))

  return { x: x, y: y, width: width, height: height, above: opensAbove }
}

function unquote(value) {
  return String(value || "").trim().replace(/^['\"]|['\"]$/g, "")
}

function parseCatalog(text) {
  var layouts = []
  var shortcuts = []
  var section = ""
  var entry = null
  var group = ""

  String(text || "").split("\n").forEach(function(line) {
    if (line === "layouts:") {
      section = "layouts"
      entry = null
      return
    }
    if (line === "option_groups:") {
      section = "options"
      entry = null
      return
    }

    if (section === "layouts") {
      var start = line.match(/^- layout:\s*(.*)$/)
      if (start) {
        entry = { layout: unquote(start[1]), variant: "", brief: "", description: "" }
        layouts.push(entry)
        return
      }
      var field = line.match(/^  (variant|brief|description):\s*(.*)$/)
      if (entry && field) entry[field[1]] = unquote(field[2])
      return
    }

    if (section === "options") {
      var groupStart = line.match(/^- name:\s*(.*)$/)
      if (groupStart) {
        group = unquote(groupStart[1])
        return
      }
      if (group !== "grp") return
      var optionStart = line.match(/^  - name:\s*(.*)$/)
      if (optionStart) {
        entry = { value: unquote(optionStart[1]), label: "" }
        shortcuts.push(entry)
        return
      }
      var description = line.match(/^    description:\s*(.*)$/)
      if (entry && description) entry.label = unquote(description[1])
    }
  })

  return {
    layouts: layouts.filter(function(item) {
      return item.layout && item.description
    }),
    shortcuts: shortcuts.filter(function(item) {
      return /^grp:/.test(item.value)
        && !/_switch(?:_|$)/.test(item.value)
        && (/_toggle(?:_|$)/.test(item.value) || /_select$/.test(item.value) || item.value === "grp:toggle")
        && item.label
    }).map(function(item) {
      return { value: item.value, label: item.label, description: item.value }
    })
  }
}

function normalizeLayouts(value) {
  if (!Array.isArray(value)) return []
  return value.filter(function(item) {
    return item && /^[A-Za-z0-9_+-]+$/.test(String(item.layout || ""))
      && (/^[A-Za-z0-9_+-]*$/.test(String(item.variant || "")))
  }).map(function(item) {
    return {
      layout: String(item.layout),
      variant: String(item.variant || ""),
      latin: item.latin === true
    }
  })
}

function findCatalogEntry(catalog, layout, variant) {
  var list = catalog && Array.isArray(catalog.layouts) ? catalog.layouts : []
  return list.find(function(item) {
    return item.layout === layout && item.variant === (variant || "")
  }) || null
}

function descriptionFor(catalog, layout, variant) {
  var item = findCatalogEntry(catalog, layout, variant)
  return item ? item.description : [layout, variant].filter(Boolean).join(" (") + (variant ? ")" : "")
}

function labelFor(catalog, layout, variant) {
  var item = findCatalogEntry(catalog, layout, variant)
  var raw = item && item.brief ? item.brief.split("-")[0] : String(layout || "")
  raw = raw.replace(/[^A-Za-z]/g, "").toUpperCase()
  if (raw.length < 2) raw += String(layout || "XX").replace(/[^A-Za-z]/g, "").toUpperCase()
  return (raw + "XX").substring(0, 2)
}

// XKB's own description doesn't always name the keyboard standard people
// search for, so the search box (which only matches label/description, see
// KeyboardSearchableDropdown.recomputeFiltered) would otherwise miss it. Keyed
// by layout code; only ever surfaced on that layout's base (no-variant) entry,
// since that's the one shipping the alias in practice.
var LAYOUT_ALIASES = {
  br: "ABNT2"
}

function aliasFor(layout) {
  return Object.prototype.hasOwnProperty.call(LAYOUT_ALIASES, layout) ? LAYOUT_ALIASES[layout] : ""
}

function baseLayoutOptions(catalog, configured) {
  var used = {}
  normalizeLayouts(configured).forEach(function(item) { used[item.layout + "\u0000" + item.variant] = true })
  var seen = {}
  var catalogLayouts = catalog && catalog.layouts ? catalog.layouts : []
  return catalogLayouts.filter(function(item) {
    if (item.variant !== "" || seen[item.layout]) return false
    seen[item.layout] = true
    return catalogLayouts.some(function(candidate) {
      return candidate.layout === item.layout && !used[candidate.layout + "\u0000" + candidate.variant]
    })
  }).map(function(item) {
    var alias = aliasFor(item.layout)
    var description = item.layout.toUpperCase() + (alias ? " · " + alias : "")
    return { value: item.layout, label: item.description, description: description }
  })
}

function variantOptions(catalog, layout, configured) {
  var used = {}
  normalizeLayouts(configured).forEach(function(item) { used[item.layout + "\u0000" + item.variant] = true })
  return (catalog && catalog.layouts ? catalog.layouts : []).filter(function(item) {
    return item.layout === layout && !used[item.layout + "\u0000" + item.variant]
  }).map(function(item) {
    return {
      value: item.variant,
      label: item.variant === "" ? "Default" : item.description,
      description: item.variant === "" ? item.description : item.variant
    }
  })
}

function duplicate(layouts, layout, variant) {
  return normalizeLayouts(layouts).some(function(item) {
    return item.layout === layout && item.variant === (variant || "")
  })
}

function canDelete(layouts, index) {
  var normalized = normalizeLayouts(layouts)
  if (normalized.length <= 1) return { ok: false, reason: "Keep at least one keyboard language." }
  if (index < 0 || index >= normalized.length) return { ok: false, reason: "That keyboard language is no longer available." }
  var next = normalized.slice(0, index).concat(normalized.slice(index + 1))
  if (next[0].latin !== true) {
    return { ok: false, reason: "Keep a Latin layout first so Quattro's SUPER+letter shortcuts continue to work." }
  }
  return { ok: true, reason: "" }
}

function eventKeyboardName(event) {
  var parts
  try { if (event && event.parse) parts = event.parse(2) } catch (error) {}
  if (!parts) parts = String(event && event.data ? event.data : "").split(",")
  var name = String(parts[0] || "")
  return name.indexOf("hl-virtual-keyboard") === 0 ? "" : name
}

function isTypedKeyboard(name) {
  return !UNTYPED_KEYBOARDS.test(String(name || ""))
}

function selectKeyboard(typed, namedByEvent) {
  var keyboards = typed || []
  return keyboards.find(function(keyboard) { return keyboard.name === namedByEvent })
    || keyboards.reduce(function(furthest, keyboard) {
      return ((keyboard && keyboard.active_layout_index) || 0) > ((furthest && furthest.active_layout_index) || 0) ? keyboard : furthest
    }, keyboards[0])
}

if (typeof module !== "undefined") module.exports = {
  aliasFor: aliasFor,
  baseLayoutOptions: baseLayoutOptions,
  canDelete: canDelete,
  descriptionFor: descriptionFor,
  duplicate: duplicate,
  eventKeyboardName: eventKeyboardName,
  findCatalogEntry: findCatalogEntry,
  heroPhrases: heroPhrases,
  isTypedKeyboard: isTypedKeyboard,
  labelFor: labelFor,
  normalizeLayouts: normalizeLayouts,
  parseCatalog: parseCatalog,
  popupPlacement: popupPlacement,
  selectKeyboard: selectKeyboard,
  variantOptions: variantOptions
}

