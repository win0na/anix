# opencode-dcp-fix

First-party vendored code, loaded by OpenCode as a local plugin. This repository is the source of truth.

Keeps internal context-management metadata out of OpenCode v2 sessions.

Three sentinels leak into what you see and what the model re-reads:

| Leak | Source |
| --- | --- |
| `<system-reminder>…</system-reminder>` | runtime notices, editor selection context |
| `<dcp-system-reminder>` | DCP pruning nudges |
| `@N@`, `@bN@` | DCP message and compressed-block references |

They are addressed to the agent and are meant to be invisible.

## What it does

Two seams, because a leak enters at one end or the other. Both are verified
against a running 2.2.5 server.

**Prompt scrubbing.** `ctx.session.hook("prompt")` rewrites `event.prompt.text`
before the prompt is admitted, so a reminder that was pasted or re-sent never
becomes a stored user message. Submitting
`… Ignore this: <system-reminder>SECRET-MARKER</system-reminder>` stored
`"… Ignore this: "`, `instr(data,'SECRET-MARKER')` on the `session_message` row
returns `0`.

**Reply scrubbing.** `ctx.session.hook("http.response")` wraps the provider
stream and sanitizes text deltas before OpenCode stores them, so a model that
echoes an injected block cannot put it in a message. Deltas are sanitized
statefully, because a block spread over several SSE events has no complete tag
in any one of them.

Checked by asking a model to repeat a file verbatim, where the file contained
`<system-reminder>ECHOLEAK99</system-reminder>`. The stored reply was
`"MARKER-START\n\nMARKER-END"`; the tag never reached the transcript.

Why not `ctx.aisdk.hook("language")`: it looks like the right seam, it hands
over a `LanguageModelV3` that can be wrapped, and it registers, but it never
fires. Instrumented runs on 2.2.5 logged `language hook registered` and then no
event at all, across two providers and two SDK adapters (`opencode-go`,
`@ai-sdk/openai-compatible`). `http.response` does fire, and the core Snowflake
provider already replaces whole responses through it.

## What it cannot do

**Existing messages.** OpenCode v2 gives plugins no way to change how a stored
message renders:

- the TUI slot tree (`SlotMap`) exposes footers, `session.panel` and
  `sidebar.content`, no transcript slot;
- `session.message` is read-only in both the server API and the TUI `Data` API;
- session parts have no write surface.

So history already in a session keeps its tags until the TUI is patched upstream.
This plugin only stops new leaks.

Tool-call arguments, provider metadata and JSON schemas are never rewritten —
DCP's `compress` placeholders live in tool arguments, so stripping there would
silently break pruning.

## Install

Add the directory to `~/.config/opencode/opencode.json`:

```json
{
  "plugins": ["~/.config/opencode/plugins/opencode-dcp-fix"]
}
```

`plugin` (singular) is the legacy key and also works. The path must be a
directory; OpenCode resolves it through the package's `name` and `exports`, so
`index.js` loads as the server entry point.

Editing plugin code requires a fresh server. `opencode run` attaches to the
long-lived background daemon, which only reloads plugin source when its watcher
notices a change to a file already in the module graph. Adding a new module (as
`lib/sse.js` was) is picked up on the next reload; anything else needs
`opencode run --standalone`, or a service restart.

Alternatively, symlink it into the auto-discovered plugin directory:

```sh
ln -s ~/.config/opencode/plugins/opencode-dcp-fix ~/.config/opencode/plugin/opencode-dcp-fix
```

## Options

The object form of a plugin entry carries options:

```json
{
  "plugins": [
    {
      "package": "~/.config/opencode/plugins/opencode-dcp-fix",
      "options": { "messageRefs": false }
    }
  ]
}
```

| Option | Default | Effect |
| --- | --- | --- |
| `systemReminders` | `true` | Strip `<system-reminder>` blocks |
| `dcpReminders` | `true` | Strip `<dcp-system-reminder>` blocks |
| `messageRefs` | `true` | Strip `@N@` / `@bN@` references |
| `collapseBlankLines` | `true` | Collapse the blank lines a removed block leaves behind |

## Trade-offs

Scrubbing means the plugin cannot tell a leak from a citation: if you paste a
tag, it is removed. The same applies to a reference, asking a model to explain
`@N@` yields nothing. Turn off `messageRefs` if you need to discuss them.
Indentation, code fences and tool arguments are untouched.

`<tag>` blocks are only removed when they are closed. A lone `<system-reminder>`
in prose is left alone, since a half-written tag is far more likely to be prose
than a real sentinel.

## Tests

```sh
node --test test/
```

38 tests: block and reference scrubbing, deltas that split a sentinel across
chunks, SSE framing and chunk boundaries, tool-argument preservation, and the
plugin wiring against a stub context.

## For existing history

The display half belongs in the TUI, where user and assistant text is rendered
straight from storage:

- `packages/tui/src/routes/session/index.tsx`, transcript rendering and the
  `## User` export path;
- `packages/tui/src/routes/session/dialog-message.tsx`, copy to clipboard.

`tui-display.patch` in this repo adds a `filterSystemMetadata()` pass over
`message.text` at those three call sites. Apply it to an OpenCode checkout:

```sh
git -C /path/to/opencode apply ~/.config/opencode/plugins/opencode-dcp-fix/tui-display.patch
```

It needs to land upstream, or into a locally built TUI, before it helps, the
shipped binary renders from storage and cannot be patched from outside.
