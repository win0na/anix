# OpenCode

OpenCode runs on both hosts from one configuration. The config, agents, skills,
and plugins are shared. Paths and secrets are host-specific and are generated
at activation.

## What is shared

| Item | Location |
| --- | --- |
| Main config | `~/.config/opencode/opencode.json` |
| TUI config | `~/.config/opencode/cli.json` |
| Agent instructions | `~/.config/opencode/AGENTS.md` |
| Plugin config | `~/.config/opencode/oh-my-opencode-slim.json`, `dcp.jsonc` |
| Prompts | `~/.config/opencode/dcp-prompts/` |
| Theme | `~/.config/opencode/themes/catppuccin-mocha.json` |
| Local plugins | `~/.config/opencode/plugins/` |
| Skills | `~/.config/opencode/skills/`, `~/.agents/skills/` |
| State | `~/.local/share/opencode/`, `~/.cache/opencode/` |

Home Manager links the read-only files with `xdg.configFile`. It copies
`opencode.json` and `cli.json` from the store at activation because OpenCode
rewrites those two. State stays on the local disk. The two skill directories are
provisioned from their own sources; the repository tracks the config that points
at them.

## Plugins

| Plugin | Source | Role |
| --- | --- | --- |
| `oh-my-opencode-slim` | npm | Agent and tool policy |
| `opencode-dcp-fix` | This repo | Strips internal context metadata from prompts and output |
| `@tarquinen/opencode-dcp` | npm | Context management |
| `@ex-machina/opencode-anthropic-auth` | npm, `2.0.0-next.6` | Anthropic auth |
| `@slkiser/opencode-quota` | npm | Quota display |
| `headroom-opencode` | npm | Context compression |
| `herdr-agent-state.js` | First-party | Reports agent state to Herdr |
| `rootshell-push.ts` | First-party | Push notifications |
| `rtk.ts` | First-party | Local tooling |

Caveman and Moshi are removed. Their plugins and MCP servers do not load on
either host.

npm plugin versions follow latest, with one exception. The Anthropic auth plugin
is pinned to `2.0.0-next.6`, the published build that works; a bare `latest`
does not resolve to that prerelease. The other npm plugins are unpinned, so a
new release reaches both hosts on the next rebuild. If a release breaks the
setup, pin that one plugin in the same commit that fixes the config.

## MCP servers

| Server | Command | Notes |
| --- | --- | --- |
| `fff` | `fff-mcp` | File search |
| `headroom` | `uvx --from headroom-ai[all] headroom mcp serve` | Context compression |
| `serena` | `uvx --from serena-agent serena start-mcp-server --project-from-cwd --context agent --open-web-dashboard False` | Code intelligence |

Use commands on `PATH`, not absolute home paths. The WSL host and the Mac have
different home directories, and a path from one host fails on the other.

Caveman MCP is not configured.

## Secrets

The 9router key lives in sops and is referenced from `opencode.json`:

```json
"apiKey": "{file:/run/secrets/opencode-9router-api-key}"
```

The sops secret is owned by `winona` with mode `0400`; both hosts read it from
`/run/secrets`. The repository contains no plaintext key. The key name in
`secrets/secrets.yaml` is `opencode/9router-api-key`, so the sops module maps it
with `key = "opencode/9router-api-key"`. A missing secret reads as an empty
string; the provider then fails auth.

`service.json` is a local secret and stays out of the repository. `auth.json`
does not exist in this setup.

## DCP fix

`opencode-dcp-fix` strips two kinds of internal metadata from the prompt and the
model output: system reminder blocks and `@N@` message references. The plugin is
vendored at `pkgs/opencode-dcp-fix` and loaded from
`~/.config/opencode/plugins/opencode-dcp-fix`. Its tests run with `node --test`.

## Herdr integration

`herdr-agent-state.js` reports the agent state to Herdr so the bar shows when
an agent is working. The Herdr layout treats the center pane as the agent or
terminal. The plugin is shared; the Herdr config is in [Herdr](herdr.md).

## Verify

```sh
opencode --version
opencode --help
opencode debug config
opencode plugin list
```

Check the generated config for absolute paths from the other host. The WSL host
uses `/home/winona`; the Mac uses `/Users/winona`. A shared file with either
path is a bug. Check that `mcp` has exactly `fff`, `headroom`, and `serena`, and
that no caveman or moshi entry survives. The checked-in config parses with
`jq empty home/winona/opencode/opencode.json`.

## Known limits

- npm plugins follow latest, so two rebuilds can load different code. The
  Anthropic auth plugin is the deliberate exception at `2.0.0-next.6`.
- Skills are large and are not vendored. A missing skill directory is a setup
  error, not a config error.
- The 9router provider uses `127.0.0.1:20128`; the headroom plugin expects the
  proxy at `127.0.0.1:8787`. Both must run on each host that uses them.
- `opencode.json` and `cli.json` are copies, not links. A manual edit is
  overwritten by the next activation.
