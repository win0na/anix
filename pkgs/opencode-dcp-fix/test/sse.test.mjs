import assert from "node:assert/strict"
import test from "node:test"
import { createSseFilter } from "../lib/sse.js"

const encode = (value) => new TextEncoder().encode(value)

/** Feed raw SSE text through the filter one chunk at a time. */
function run(chunks, options) {
  const filter = createSseFilter(options)
  let out = ""
  for (const chunk of chunks) out += filter.write(encode(chunk))
  out += filter.flush()
  return out.split("\n").filter((line) => line.startsWith("data: "))
}

const openai = (delta) => `data: ${JSON.stringify({ choices: [{ index: 0, delta }] })}\n\n`

/** Collected `content` of each delta, in order. */
function content(lines) {
  return lines
    .map((line) => line.slice("data: ".length))
    .filter((body) => !body.startsWith("["))
    .map((body) => JSON.parse(body)?.choices?.[0]?.delta?.content ?? "")
    .join("")
}

test("passes ordinary deltas through unchanged", () => {
  const lines = run([openai({ content: "hello " }), openai({ content: "world" }), "data: [DONE]\n\n"])
  assert.equal(content(lines), "hello world")
  assert.equal(lines.at(-1), "data: [DONE]")
})

test("strips a block that arrives inside one delta", () => {
  const lines = run([openai({ content: "a<system-reminder>secret</system-reminder>b" })])
  assert.equal(content(lines), "ab")
})

test("strips a block split across deltas", () => {
  const lines = run([
    openai({ content: "a<system-rem" }),
    openai({ content: "inder>sec" }),
    openai({ content: "ret</system-reminder" }),
    openai({ content: ">b" }),
  ])
  assert.equal(content(lines), "ab")
})

test("never emits the start of a block it later drops", () => {
  const lines = run([openai({ content: "x<system-remin" }), openai({ content: "der>gone</system-reminder>y" })])
  assert.equal(content(lines), "xy")
  assert.ok(!lines.join("").includes("system-remin\""))
})

test("strips dcp reminders and reference tokens", () => {
  const lines = run([
    openai({ content: "see @4@ and " }),
    openai({ content: "<dcp-system-reminder>nudge</dcp-system-reminder>" }),
    openai({ content: " @b2@ done" }),
  ])
  assert.equal(content(lines), "see  and   done")
})

test("honours messageRefs: false", () => {
  const lines = run([openai({ content: "keep @4@ here" })], { messageRefs: false })
  assert.equal(content(lines), "keep @4@ here")
})

test("leaves tool-call arguments alone", () => {
  const payload = {
    choices: [
      {
        index: 0,
        delta: {
          tool_calls: [
            {
              index: 0,
              function: { name: "compress", arguments: '{"block":"@b2@","text":"<system-reminder>x</system-reminder>"}' },
            },
          ],
        },
      },
    ],
  }
  const lines = run([`data: ${JSON.stringify(payload)}\n\n`])
  const parsed = JSON.parse(lines[0].slice("data: ".length))
  assert.equal(parsed.choices[0].delta.tool_calls[0].function.arguments, payload.choices[0].delta.tool_calls[0].function.arguments)
})

test("keeps non-text fields intact", () => {
  const lines = run([openai({ role: "assistant" }), openai({ content: "ok" })])
  const first = JSON.parse(lines[0].slice("data: ".length))
  assert.equal(first.choices[0].delta.role, "assistant")
})

test("sanitizes anthropic text deltas", () => {
  const sse = (delta) =>
    `event: content_block_delta\ndata: ${JSON.stringify({ type: "content_block_delta", index: 0, delta })}\n\n`
  const filter = createSseFilter()
  let out = filter.write(encode(sse({ type: "text_delta", text: "a<system-reminder>" })))
  out += filter.write(encode(sse({ type: "text_delta", text: "gone" })))
  out += filter.write(encode(sse({ type: "text_delta", text: "</system-reminder>b" })))
  out += filter.flush()
  const text = out
    .split("\n")
    .filter((line) => line.startsWith("data: "))
    .map((line) => JSON.parse(line.slice("data: ".length)))
    .filter((item) => item.type === "content_block_delta")
    .map((item) => item.delta.text)
    .join("")
  assert.equal(text, "ab")
})

test("keeps event and comment lines", () => {
  const lines = run(["event: ping\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"hi\"}}]}\n\n"])
  assert.deepEqual(lines, ['data: {"choices":[{"index":0,"delta":{"content":"hi"}}]}'])
})

test("survives a line split across chunks", () => {
  const filter = createSseFilter()
  const full = openai({ content: "split line" })
  let out = ""
  for (const char of full) out += filter.write(encode(char))
  out += filter.flush()
  const lines = out.split("\n").filter((line) => line.startsWith("data: "))
  assert.equal(content(lines), "split line")
})

test("passes malformed payloads through", () => {
  const lines = run(["data: {not json}\n\n"])
  assert.deepEqual(lines, ["data: {not json}"])
})
