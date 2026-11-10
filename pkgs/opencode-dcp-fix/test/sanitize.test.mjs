import assert from "node:assert/strict"
import test from "node:test"

import { createStreamSanitizer, isDirty, sanitize } from "../lib/sanitize.js"

const BLOCK = "<system-reminder>Note: the user opened a.ts</system-reminder>"
const DCP = "<dcp-system-reminder>Compress if a span is closed.</dcp-system-reminder>"

test("removes a system-reminder block", () => {
  assert.equal(sanitize(`hello\n${BLOCK}\nworld`), "hello\n\nworld")
})

test("removes a multi-line block", () => {
  const block = "<system-reminder>\nline one\nline two\n</system-reminder>"
  assert.equal(sanitize(`a${block}b`), "ab")
})

test("removes a dcp block without eating a system-reminder block", () => {
  assert.equal(sanitize(`${DCP}\n${BLOCK}\nkeep me`), "\n\nkeep me")
})

test("leaves an unterminated tag alone", () => {
  const text = "compare <system-reminder> with </wrong> tags"
  assert.equal(sanitize(text), text)
})

test("removes message and block references", () => {
  assert.equal(sanitize("see @12@ and @b3@ here"), "see  and  here")
})

test("keeps ordinary at-signs", () => {
  const text = "mail me at user@example.com, handle @winona"
  assert.equal(sanitize(text), text)
})

test("collapses blank lines left behind", () => {
  assert.equal(sanitize(`a\n${BLOCK}\n\n\nb`), "a\n\nb")
})

test("preserves indentation", () => {
  const text = "```\n  indented\n\tmore\n```"
  assert.equal(sanitize(text), text)
})

test("reports whether anything changed", () => {
  assert.equal(isDirty(`a${BLOCK}b`), true)
  assert.equal(isDirty("clean text"), false)
})

test("options can disable a rule", () => {
  assert.equal(sanitize(BLOCK, { systemReminders: false }), BLOCK)
  assert.equal(sanitize("see @12@", { messageRefs: false }), "see @12@")
})

test("stream keeps plain text intact", () => {
  const stream = createStreamSanitizer()
  let out = ""
  for (const delta of ["Hel", "lo, ", "world"]) out += stream.push(delta)
  out += stream.flush()
  assert.equal(out, "Hello, world")
})

test("stream drops a block split across deltas", () => {
  const stream = createStreamSanitizer()
  let out = ""
  for (const delta of ["before ", "<system-remi", "nder>hidden", " text</system-", "reminder> after"]) out += stream.push(delta)
  out += stream.flush()
  assert.equal(out, "before  after")
})

test("stream never emits the start of a block it later drops", () => {
  const stream = createStreamSanitizer()
  let out = ""
  for (const delta of ["<", "sys", "tem-reminder>", "x", "</system-reminder>"]) out += stream.push(delta)
  out += stream.flush()
  assert.equal(out, "")
})

test("stream drops a reference split across deltas", () => {
  const stream = createStreamSanitizer()
  let out = ""
  for (const delta of ["about ", "@1", "2", "@", " done"]) out += stream.push(delta)
  out += stream.flush()
  assert.equal(out, "about  done")
})

test("stream holds a trailing sentinel until flush", () => {
  const stream = createStreamSanitizer()
  assert.equal(stream.push("text <dcp-"), "text ")
  assert.equal(stream.flush(), "")
})

test("stream keeps a truncated reference at end of stream", () => {
  const stream = createStreamSanitizer()
  assert.equal(stream.push("ping @42"), "ping ")
  assert.equal(stream.flush(), "@42")
})

test("stream does not hold text that only resembles a tag", () => {
  const stream = createStreamSanitizer()
  let out = stream.push("use <div> here ")
  out += stream.push("ok")
  out += stream.flush()
  assert.equal(out, "use <div> here ok")
})
