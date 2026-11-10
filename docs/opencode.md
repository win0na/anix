# OpenCode

OpenCode runs on both hosts from one configuration. The config, agents, skills,
and plugins are shared. Paths and secrets are host-specific and are generated
at activation.

## What is shared

| Item | Location |
| --- | --- |
| Main config | `~/.config/opencode/opencode.json` |
| Agent instructions | `~/.config/opencode/AGENTS.md` |
| Plugin config | `~/.config/opencode/oh-my-opencode-slim.json`, `dcp.jsonc` |
| Local plugins | `~/.config/opencode/plugins/` |
| Skills | `~/.config/opencode/skills/`, `~/.agents/skills/` |
| State | `~/.local/share/opencode/`, `~/.cache/opencode/` |

Home Manager writes the config files. State stays on the local disk. The two
skill directories are provisioned from their own sources; the repository tracks
the config that points at them.

## Plugins

| Plugin | Source | Role |
| --- | --- | --- |
| `oh-my-opencode-slim` | npm | Agent and tool policy |
| `opencode-dcp-fix` | This repo | Strips internal context metadata from prompts and output |
| `@tarquinen/opencode-dcp` | npm | Context management |
| `@ex-machina/opencode-anthropic-auth` | npm | Anthropic auth |
| `@slkiser/opencode-quota` | npm | Quota display |
| `headroom-opencode` | npm | Context compression |
| `herdr-agent-state.js` | First-party | Reports agent state to Herdr |
| `rootshell-push.ts` | First-party | Push notifications |
| `rtk.ts` | First-party | Local tooling |

Caveman and Moshi are removed. Their plugins and MCP servers do not load on
either host.

npm plugin versions follow latest. The repository does not pin them, so a new
upstream release reaches both hosts on the next rebuild. If a release breaks
the setup, pin that one plugin in the same commit that fixes the config.

## MCP servers

| Server | Command | Notes |
| --- | --- | --- |
| `fff` | `fff-mcp` | File search |
| `headroom` | `headroom mcp serve` | Context compression |
| `serena` | `uvx --from serena-agent serena start-mcp-server --project-from-cwd --context agent --open-web-dashboard False` | Code intelligence |

Use commands on `PATH`, not absolute home paths. The WSL host and the Mac have
different home directories, and a path from one host fails on the other.

Caveman MCP is not configured.

## Secrets

API keys do not live in `opencode.json`. Home Manager writes the file from a
sops template, or exports the keys into the OpenCode environment at login. The
exact template lands in the configuration pass. The rule is fixed: the
repository contains no plaintext key, and the generated file is not edited by
hand.

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
```

Check the generated config for absolute paths from the other host. The WSL host
uses `/home/winona`; the Mac uses `/Users/winona`. A shared file with either
path is a bug.

## Known limits

- npm plugins follow latest, so two rebuilds can load different code.
- Skills are large and are not vendored. A missing skill directory is a setup
  error, not a config error.
- The auth plugin may require a prerelease version. If latest fails, pin the
  known working prerelease for that plugin only.
