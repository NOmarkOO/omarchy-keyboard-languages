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
      alias: aliasError(item.alias) === "" ? normalizeAlias(item.alias) : "",
      latin: item.latin === true
    }
  })
}

function normalizeAlias(value) {
  return String(value || "").trim()
}

function aliasLength(value) {
  var text = String(value || "")
  var length = 0
  for (var index = 0; index < text.length; index++) {
    var first = text.charCodeAt(index)
    if (first >= 0xD800 && first <= 0xDBFF && index + 1 < text.length) {
      var second = text.charCodeAt(index + 1)
      if (second >= 0xDC00 && second <= 0xDFFF) index++
    }
    length++
  }
  return length
}

function aliasError(value) {
  var raw = String(value || "")
  if (/[\u0000-\u001F\u007F-\u009F]/.test(raw)) return "Aliases cannot contain control characters."
  if (aliasLength(normalizeAlias(raw)) > 6) return "Use 6 characters or fewer."
  return ""
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

function labelFor(catalog, layout, variant, alias) {
  var custom = normalizeAlias(alias)
  if (custom && aliasError(alias) === "") return custom
  var item = findCatalogEntry(catalog, layout, variant)
  var raw = item && item.brief ? item.brief.split("-")[0] : String(layout || "")
  raw = raw.replace(/[^A-Za-z]/g, "").toUpperCase()
  if (raw.length < 2) raw += String(layout || "XX").replace(/[^A-Za-z]/g, "").toUpperCase()
  return (raw + "XX").substring(0, 2)
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
    return { value: item.layout, label: item.description, description: item.layout.toUpperCase() }
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

// Recent-first ("macOS-style") switching. A history is the list of layout
// indexes ordered from most to least recently used. Presses that arrive close
// together form one burst: the first press snapshots the history and steps to
// the previous layout, every further press goes one layout deeper, and the
// burst only reorders the history once it is committed.
function recentInitial() {
  return { order: [], base: null, position: 0 }
}

function recentNormalize(order, count) {
  var seen = {}
  var result = []
  ;(Array.isArray(order) ? order : []).forEach(function(value) {
    if (Number.isInteger(value) && value >= 0 && value < count && !seen[value]) {
      seen[value] = true
      result.push(value)
    }
  })
  for (var index = 0; index < count; index++) {
    if (!seen[index]) result.push(index)
  }
  return result
}

function recentMoveToFront(order, index) {
  return [index].concat(order.filter(function(value) { return value !== index }))
}

// Records a layout change that happened outside a burst (click on a row, an XKB
// shortcut, another tool). Changes reported while a burst runs are its own hops.
function recentNote(state, active, count) {
  if (state.base || !Number.isInteger(active) || active < 0 || active >= count) return state
  return { order: recentMoveToFront(recentNormalize(state.order, count), active), base: null, position: 0 }
}

function recentPress(state, active, count) {
  var order = recentNormalize(state.order, count)
  var base = state.base
  var position = state.position
  if (!base || base.length !== count) {
    order = recentMoveToFront(order, Number.isInteger(active) && active >= 0 && active < count ? active : order[0])
    base = order
    position = 0
  }
  position = (position + 1) % base.length
  return { state: { order: order, base: base, position: position }, target: base[position] }
}

function recentCommit(state) {
  if (!state.base) return state
  return { order: recentMoveToFront(state.base, state.base[state.position]), base: null, position: 0 }
}

if (typeof module !== "undefined") module.exports = {
  aliasLength: aliasLength,
  aliasError: aliasError,
  baseLayoutOptions: baseLayoutOptions,
  canDelete: canDelete,
  descriptionFor: descriptionFor,
  duplicate: duplicate,
  eventKeyboardName: eventKeyboardName,
  findCatalogEntry: findCatalogEntry,
  heroPhrases: heroPhrases,
  isTypedKeyboard: isTypedKeyboard,
  labelFor: labelFor,
  normalizeAlias: normalizeAlias,
  normalizeLayouts: normalizeLayouts,
  parseCatalog: parseCatalog,
  popupPlacement: popupPlacement,
  recentCommit: recentCommit,
  recentInitial: recentInitial,
  recentMoveToFront: recentMoveToFront,
  recentNormalize: recentNormalize,
  recentNote: recentNote,
  recentPress: recentPress,
  selectKeyboard: selectKeyboard,
  variantOptions: variantOptions
}
