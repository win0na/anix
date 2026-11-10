import assert from "node:assert/strict"
import test from "node:test"

import plugin from "../index.js"

const BLOCK = "<system-reminder>opened a.ts</system-reminder>"

/** Minimal stand-in for the OpenCode plugin context. */
function fakeContext(options) {
  const hooks = { prompt: [], "http.response": [], disposed: 0 }
  const ctx = {
    options,
    session: {
      hook: async (name, handler) => {
        hooks[name].push(handler)
        return { dispose: async () => void (hooks.disposed += 1) }
      },
    },
  }
  return { ctx, hooks }
}

function sse(delta) {
  return new Response(`data: ${JSON.stringify({ choices: [{ index: 0, delta }] })}\n\n`, {
    headers: { "content-type": "text/event-stream" },
  })
}

test("exposes the plugin shape OpenCode loads", () => {
  assert.equal(typeof plugin.id, "string")
  assert.equal(typeof plugin.setup, "function")
})

test("registers both hooks and returns a cleanup", async () => {
  const { ctx, hooks } = fakeContext({})
  const cleanup = await plugin.setup(ctx)
  assert.equal(hooks.prompt.length, 1)
  assert.equal(hooks["http.response"].length, 1)
  assert.equal(typeof cleanup, "function")
  await cleanup()
  assert.equal(hooks.disposed, 2)
})

test("strips a reminder out of a submitted prompt", async () => {
  const { ctx, hooks } = fakeContext({})
  await plugin.setup(ctx)
  const event = { sessionID: "s", messageID: "m", prompt: { text: `why is this here?\n${BLOCK}\nthanks` } }
  hooks.prompt[0](event)
  assert.equal(event.prompt.text, "why is this here?\n\nthanks")
})

test("leaves a clean prompt untouched", async () => {
  const { ctx, hooks } = fakeContext({})
  await plugin.setup(ctx)
  const event = { prompt: { text: "plain question" } }
  hooks.prompt[0](event)
  assert.equal(event.prompt.text, "plain question")
})

test("honors per-rule options", async () => {
  const { ctx, hooks } = fakeContext({ messageRefs: false })
  await plugin.setup(ctx)
  const event = { prompt: { text: `keep ${BLOCK} drop` } }
  hooks.prompt[0](event)
  assert.equal(event.prompt.text, "keep  drop")
})

test("tolerates an event without prompt text", async () => {
  const { ctx, hooks } = fakeContext({})
  await plugin.setup(ctx)
  const event = {}
  assert.doesNotThrow(() => hooks.prompt[0](event))
})

test("rewrites a provider stream in place", async () => {
  const { ctx, hooks } = fakeContext({})
  await plugin.setup(ctx)
  const event = { response: sse({ content: "a<system-reminder>drop</system-reminder>b" }) }
  await hooks["http.response"][0](event)
  assert.notEqual(event.response, undefined)
  const body = await event.response.text()
  const content = JSON.parse(body.split("\n")[0].slice("data: ".length)).choices[0].delta.content
  assert.equal(content, "ab")
})

test("ignores responses that are not event streams", async () => {
  const { ctx, hooks } = fakeContext({})
  await plugin.setup(ctx)
  const original = new Response("{}", { headers: { "content-type": "application/json" } })
  const event = { response: original }
  await hooks["http.response"][0](event)
  assert.equal(event.response, original)
})

test("ignores a response without a body", async () => {
  const { ctx, hooks } = fakeContext({})
  await plugin.setup(ctx)
  const event = { response: { headers: new Headers({ "content-type": "text/event-stream" }), body: null } }
  assert.doesNotThrow(() => hooks["http.response"][0](event))
})
