/**
 * opencode-dcp-fix
 *
 * Keeps internal context-management metadata out of what you see:
 *
 *   <system-reminder>…</system-reminder>
 *   <dcp-system-reminder>…</dcp-system-reminder>
 *   @12@, @b3@
 *
 * Two seams, because a leak can enter at either end:
 *
 *   session.hook("prompt")        scrub before a submitted prompt is stored
 *   session.hook("http.response") scrub provider deltas before they are stored
 *
 * The first stops pasted or re-sent reminders. The second stops a model that
 * echoes a block back into its reply.
 *
 * Options arrive through the object form of a plugin entry:
 *
 *   plugins: [{ package: "/home/winona/opencode-dcp-fix", options: { messageRefs: false } }]
 */

import { resolveOptions, sanitize } from "./lib/sanitize.js"
import { createSseFilter } from "./lib/sse.js"

const plugin = {
  id: "opencode-dcp-fix",
  setup,
}

export default plugin

/** @param {any} ctx */
async function setup(ctx) {
  const clean = resolveOptions(ctx?.options ?? {})

  const prompt = await ctx.session.hook("prompt", (event) => {
    const text = event?.prompt?.text
    if (typeof text !== "string" || text.length === 0) return
    const next = sanitize(text, clean)
    if (next !== text) event.prompt.text = next
  })

  const response = await ctx.session.hook("http.response", (event) => {
    const source = event?.response
    if (!source || !source.body) return
    if (!(source.headers.get("content-type") ?? "").includes("text/event-stream")) return

    const filter = createSseFilter(clean)
    const encoder = new TextEncoder()
    const body = source.body.pipeThrough(
      new TransformStream({
        transform(chunk, controller) {
          const out = filter.write(chunk)
          if (out.length > 0) controller.enqueue(encoder.encode(out))
        },
        flush(controller) {
          const out = filter.flush()
          if (out.length > 0) controller.enqueue(encoder.encode(out))
        },
      }),
    )

    const headers = new Headers(source.headers)
    // The body is re-encoded below, so any length or encoding from the
    // provider would be wrong.
    headers.delete("content-length")
    headers.delete("content-encoding")

    event.response = new Response(body, {
      status: source.status,
      statusText: source.statusText,
      headers,
    })
  })

  return async () => {
    await prompt?.dispose?.()
    await response?.dispose?.()
  }
}
