/**
 * Response-body sanitizer for provider streams.
 *
 * Provider replies arrive as SSE: one `data: {json}` line per delta. A model
 * that echoes an internal block therefore spreads it across several events, so
 * chunks have to be sanitized with state carried between them.
 *
 * Only text-bearing fields are rewritten. Tool-call arguments, JSON schemas and
 * provider metadata pass through untouched.
 */

import { createStreamSanitizer } from "./sanitize.js"

/** Object keys whose string value is model-visible text. */
const TEXT_KEYS = new Set(["text", "content", "reasoning", "reasoning_content"])

/**
 * @param {Partial<import("./sanitize.js").RunOptions>} [options]
 */
export function createSseFilter(options) {
  /** One sanitizer per text stream, e.g. `choices.0.delta.content`. */
  const streams = new Map()
  const decoder = new TextDecoder()
  let buffer = ""

  const stream = (key) => {
    let current = streams.get(key)
    if (!current) {
      current = createStreamSanitizer(options)
      streams.set(key, current)
    }
    return current
  }

  const walk = (node, path) => {
    if (Array.isArray(node)) {
      for (let index = 0; index < node.length; index++) walk(node[index], `${path}.${index}`)
      return
    }
    if (!node || typeof node !== "object") return
    for (const [key, value] of Object.entries(node)) {
      if (typeof value === "string" && TEXT_KEYS.has(key)) {
        node[key] = stream(`${path}.${key}`).push(value)
      } else if (value && typeof value === "object") {
        walk(value, `${path}.${key}`)
      }
    }
  }

  /** @param {string} line @returns {string} */
  const rewrite = (line) => {
    if (!line.startsWith("data:")) return line
    const body = line.slice(5).trimStart()
    // `[DONE]` markers and any other non-object payload.
    if (body.length === 0 || body.startsWith("[")) return line
    let parsed
    try {
      parsed = JSON.parse(body)
    } catch {
      return line
    }
    if (!parsed || typeof parsed !== "object") return line
    walk(parsed, "")
    return `data: ${JSON.stringify(parsed)}`
  }

  return {
    /** @param {Uint8Array} chunk @returns {string} text ready to enqueue */
    write(chunk) {
      buffer += decoder.decode(chunk, { stream: true })
      const lines = buffer.split("\n")
      buffer = lines.pop() ?? ""
      let out = ""
      for (const line of lines) out += `${rewrite(line)}\n`
      return out
    },
    /**
     * Release the decoder and drop the held tail. A tail is only held when it
     * could still become an internal tag, so dropping it is the desired end
     * state rather than a loss of visible text.
     */
    flush() {
      let out = ""
      const rest = buffer + decoder.decode()
      buffer = ""
      if (rest.length > 0) out += `${rewrite(rest)}\n`
      for (const current of streams.values()) current.flush()
      return out
    },
  }
}
