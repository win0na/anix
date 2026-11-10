/**
 * Text sanitizers for internal context-management metadata.
 *
 * OpenCode's context-pruning plugins mark up prompts and model output with
 * sentinels that only the agent is supposed to read:
 *
 *   <system-reminder>...</system-reminder>          ambient runtime notices
 *   <dcp-system-reminder>...</dcp-system-reminder>  pruning nudges
 *   @3@, @b1@                                       message and block references
 *
 * They are meant to be invisible, so any copy that reaches a prompt or a
 * rendered reply is a leak.
 */

/** Tag names whose whole `<tag>...</tag>` block is internal. */
const TAGS = Object.freeze(["dcp-system-reminder", "system-reminder"])

/** A complete reference token, e.g. `@12@` or `@b3@`. */
const REF = /@b?\d+@/g

/** A reference token still being typed, at the very end of a buffer. */
const REF_TAIL = /@b?\d*$/

export const DEFAULTS = Object.freeze({
  systemReminders: true,
  dcpReminders: true,
  messageRefs: true,
  collapseBlankLines: true,
})

/**
 * @param {Record<string, unknown>} [options]
 * @returns {typeof DEFAULTS}
 */
export function resolveOptions(options) {
  const input = options ?? {}
  const read = (key) => (typeof input[key] === "boolean" ? input[key] : DEFAULTS[key])
  return {
    systemReminders: read("systemReminders"),
    dcpReminders: read("dcpReminders"),
    messageRefs: read("messageRefs"),
    collapseBlankLines: read("collapseBlankLines"),
  }
}

/** @returns {string[]} tag names enabled by `options`, longest first. */
export function activeTags(options) {
  const opts = /** @type {typeof DEFAULTS} */ (options)
  return TAGS.filter((tag) => (tag === "system-reminder" ? opts.systemReminders : opts.dcpReminders))
    // `dcp-system-reminder` contains `system-reminder`; strip the longer tag first.
    .sort((a, b) => b.length - a.length)
}

/**
 * Remove a whole `<tag>...</tag>` block. Unterminated blocks are left alone:
 * a half-written tag is far more likely to be prose than a real sentinel.
 *
 * @param {string} text
 * @param {string} tag
 */
function stripBlock(text, tag) {
  const open = `<${tag}>`
  const close = `</${tag}>`
  let out = text
  for (;;) {
    const lower = out.toLowerCase()
    const start = lower.indexOf(open)
    if (start === -1) return out
    const end = lower.indexOf(close, start + open.length)
    if (end === -1) return out
    out = out.slice(0, start) + out.slice(end + close.length)
  }
}

/**
 * Collapse the blank space left behind by a removed block without touching
 * indentation or code fences.
 *
 * @param {string} text
 */
function collapse(text) {
  return text
    .split("\n")
    .map((line) => line.replace(/[ \t]+$/, ""))
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
}

/**
 * Sanitize a complete string.
 *
 * @param {string} text
 * @param {Partial<typeof DEFAULTS>} [options]
 * @returns {string}
 */
export function sanitize(text, options) {
  if (typeof text !== "string" || text.length === 0) return text
  const opts = resolveOptions(options)
  let out = text
  for (const tag of activeTags(opts)) out = stripBlock(out, tag)
  if (opts.messageRefs) out = out.replace(REF, "")
  if (opts.collapseBlankLines) out = collapse(out)
  return out
}

/**
 * True when `text` differs from its sanitized form, i.e. something was removed.
 *
 * @param {string} text
 * @param {Partial<typeof DEFAULTS>} [options]
 */
export function isDirty(text, options) {
  return typeof text === "string" && sanitize(text, options) !== text
}

/**
 * Sanitizer for streamed text, where a sentinel can arrive split across two
 * deltas. Text is emitted as soon as it cannot be part of a sentinel; only an
 * open tag or a partial reference is held back.
 *
 * @param {Partial<typeof DEFAULTS>} [options]
 */
export function createStreamSanitizer(options) {
  const opts = resolveOptions(options)
  const tags = activeTags(opts)
  const opens = tags.map((tag) => `<${tag}>`)
  /** Longest suffix that could still grow into an open tag. */
  const maxHold = opens.reduce((max, open) => Math.max(max, open.length - 1), 0)
  let pending = ""

  /** @param {string} buffer @returns {string} */
  const tagPrefix = (buffer) => {
    const limit = Math.min(buffer.length, maxHold)
    for (let length = limit; length > 0; length--) {
      const tail = buffer.slice(-length)
      for (const open of opens) if (open.startsWith(tail)) return tail
    }
    return ""
  }

  /**
   * Split a buffer into the part that is safe to emit now and the part that
   * must wait for more input.
   *
   * @param {string} buffer
   * @param {boolean} final
   * @returns {{ emit: string, hold: string }}
   */
  const split = (buffer, final) => {
    // Complete references are safe to drop for good; partial ones are not.
    let rest = opts.messageRefs ? buffer.replace(REF, "") : buffer
    const ref = opts.messageRefs ? (rest.match(REF_TAIL)?.[0] ?? "") : ""
    if (ref) rest = rest.slice(0, rest.length - ref.length)
    if (final) {
      // A truncated reference is still plausible prose, so keep it. A bare tag
      // fragment is not, so a stream that ends mid-tag drops it.
      const restored = rest + ref
      return { emit: restored.length > 0 && tagPrefix(restored) === restored ? "" : restored, hold: "" }
    }
    const tag = tagPrefix(rest)
    if (tag) rest = rest.slice(0, rest.length - tag.length)
    return { emit: rest, hold: tag + ref }
  }

  /** @param {boolean} final @returns {string} */
  const drain = (final) => {
    let released = ""
    for (;;) {
      const lower = pending.toLowerCase()
      let hit = -1
      let tag = ""
      for (let index = 0; index < opens.length; index++) {
        const at = lower.indexOf(opens[index])
        if (at !== -1 && (hit === -1 || at < hit)) {
          hit = at
          tag = tags[index]
        }
      }
      if (hit === -1) break
      const open = `<${tag}>`
      const close = `</${tag}>`
      const end = lower.indexOf(close, hit + open.length)
      if (end !== -1) {
        pending = pending.slice(0, hit) + pending.slice(end + close.length)
        continue
      }
      // An open tag with no close yet: everything before it is safe, and at
      // the end of a stream the unfinished block itself is internal too.
      const before = pending.slice(0, hit)
      if (final) {
        pending = ""
        return released + sanitize(split(before, true).emit, opts)
      }
      pending = pending.slice(hit)
      return released + split(before, false).emit
    }

    if (final) {
      const tail = split(pending, true)
      pending = ""
      return released + sanitize(tail.emit, opts)
    }
    const tail = split(pending, false)
    pending = tail.hold
    return released + tail.emit
  }

  return {
    /** @param {string} delta @returns {string} text that is safe to emit now */
    push(delta) {
      if (typeof delta !== "string" || delta.length === 0) return ""
      pending += delta
      return drain(false)
    },
    /** @returns {string} whatever is still held back */
    flush() {
      return drain(true)
    },
  }
}
