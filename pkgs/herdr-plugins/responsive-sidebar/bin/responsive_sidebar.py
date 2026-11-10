#!/usr/bin/env python3
"""Width-aware companion for the herdr-sidebar plugin.

The core dashboard is client-side chrome and has no plugin API. This plugin
only owns the server-side herdr-sidebar pane:

  wide tab   -> docked split, managed by herdr-sidebar itself
  narrow tab -> full-screen overlay, opened by this plugin

A detached watcher polls `session.snapshot` because herdr does not deliver
resize or layout events to plugin hooks. Tab `area.width` is the width of the
tab surface, so opening or closing a split does not move the breakpoint.
"""

from __future__ import annotations

import json
import os
import signal
import socket
import sys
import time
from pathlib import Path
from typing import Any

DEFAULTS: dict[str, Any] = {
    # Tab-surface width in columns. 110 keeps the sidebar off a phone in
    # portrait (about 78 cols at font size 9) and off an iPad in portrait
    # with the dashboard open (about 91 cols), while an iPad in landscape
    # (about 148 cols) docks it.
    "min_columns": 110,
    "poll_ms": 250,
    "sidebar_plugin": "herdr-sidebar",
    "sidebar_entrypoint": "sidebar",
    "dock_action": "open-sidebar",
    "sidebar_process": "herdr-sidebar",
    "sidebar_labels": ["Sidebar", "Source Control"],
    # Open the focused tab when the watcher starts, and when focus moves to
    # a wide tab that has no sidebar. herdr-sidebar's own auto_open is turned
    # off so its focus hooks do not fight this watcher.
    "open_on_start": True,
    "open_on_focus": True,
    "close_narrow": True,
    # A failed or snoozed open is retried no more often than this.
    "open_retry_seconds": 15,
    "log_lines": 400,
}


class ApiError(RuntimeError):
    pass


def plugin_dir() -> Path:
    return Path(os.environ.get("HERDR_PLUGIN_ROOT", Path(__file__).resolve().parent.parent))


def config_dir() -> Path:
    value = os.environ.get("HERDR_PLUGIN_CONFIG_DIR")
    return Path(value) if value else Path.home() / ".config/herdr/plugins/config/responsive-sidebar"


def state_dir() -> Path:
    value = os.environ.get("HERDR_PLUGIN_STATE_DIR")
    return Path(value) if value else Path.home() / ".local/state/herdr/plugins/responsive-sidebar"


def socket_path() -> str:
    value = os.environ.get("HERDR_SOCKET_PATH")
    if value:
        return value
    return str(Path.home() / ".config/herdr/herdr.sock")


def load_config() -> dict[str, Any]:
    cfg = dict(DEFAULTS)
    path = config_dir() / "config.json"
    if path.exists():
        try:
            loaded = json.loads(path.read_text())
            if isinstance(loaded, dict):
                cfg.update(loaded)
        except (OSError, ValueError):
            pass
    else:
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(DEFAULTS, indent=2) + "\n")
        except OSError:
            pass
    return cfg


def api(method: str, params: dict[str, Any] | None = None, timeout: float = 3.0) -> dict[str, Any]:
    request = {
        "id": f"responsive-sidebar:{method}:{time.time_ns()}",
        "method": method,
        "params": params or {},
    }
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect(socket_path())
        sock.sendall(json.dumps(request).encode() + b"\n")
        data = b""
        while not data.endswith(b"\n"):
            chunk = sock.recv(65536)
            if not chunk:
                break
            data += chunk
    finally:
        sock.close()
    if not data:
        raise ApiError(f"{method}: empty response")
    response = json.loads(data.decode())
    if "error" in response:
        raise ApiError(f"{method}: {response['error']}")
    result = response.get("result", {})
    if isinstance(result, dict) and result.get("type") == "error":
        raise ApiError(f"{method}: {result}")
    return result


def snapshot() -> dict[str, Any]:
    result = api("session.snapshot")
    snap = result.get("snapshot")
    if not isinstance(snap, dict):
        raise ApiError("session.snapshot: no snapshot")
    return snap


def layouts_by_tab(snap: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {layout["tab_id"]: layout for layout in snap.get("layouts", []) if "tab_id" in layout}


def panes_in_tab(snap: dict[str, Any], tab_id: str) -> list[dict[str, Any]]:
    return [pane for pane in snap.get("panes", []) if pane.get("tab_id") == tab_id]


def is_sidebar(pane: dict[str, Any], cfg: dict[str, Any]) -> bool:
    process = (pane.get("foreground_process") or {}).get("name", "")
    if process == cfg["sidebar_process"]:
        return True
    # Manual labels are exact ("Sidebar", "Source Control"). Never match the
    # terminal title: an agent session is free to be called "herdr-sidebar
    # crash diagnosis", and closing that pane would kill the agent.
    label = str(pane.get("label") or "").strip().lower()
    return label in {item.strip().lower() for item in cfg["sidebar_labels"]}


def docked_sidebars(snap: dict[str, Any], layout: dict[str, Any], cfg: dict[str, Any]) -> list[str]:
    tiled = {pane["pane_id"] for pane in layout.get("panes", []) if "pane_id" in pane}
    # An overlay can appear in the tab layout while it is open. Never treat a
    # pane this plugin opened as a docked sidebar.
    overlays = set(load_overlays().values())
    return [
        pane["pane_id"]
        for pane in panes_in_tab(snap, layout["tab_id"])
        if pane.get("pane_id") in tiled
        and pane.get("pane_id") not in overlays
        and is_sidebar(pane, cfg)
    ]


def try_close(pane_id: str, plugin_pane: bool = False) -> bool:
    """Close a docked pane with pane.close, or an overlay with
    plugin.pane.close. The generic pane.close refuses overlay panes."""
    method = "plugin.pane.close" if plugin_pane else "pane.close"
    try:
        api(method, {"pane_id": pane_id})
        return True
    except (ApiError, OSError, ValueError):
        return False


def focus_new_sidebar(before: set[str], tab_id: str, cfg: dict[str, Any]) -> None:
    """The watcher opens with focus_on_open=false so auto-dock never steals
    keystrokes. A manual toggle should still leave the cursor in the sidebar,
    so wait for the new docked pane and focus it explicitly."""
    for _ in range(12):
        time.sleep(0.15)
        try:
            snap = snapshot()
            layout = layouts_by_tab(snap).get(tab_id)
            if not layout:
                return
            for pane_id in docked_sidebars(snap, layout, cfg):
                if pane_id not in before:
                    api("plugin.pane.focus", {"pane_id": pane_id})
                    return
        except (ApiError, OSError, ValueError):
            return


def open_dock(layout: dict[str, Any], cfg: dict[str, Any]) -> None:
    focused = layout.get("focused_pane_id")
    context = {
        "workspace_id": layout.get("workspace_id"),
        "tab_id": layout.get("tab_id"),
    }
    if focused:
        context["focused_pane_id"] = focused
    api(
        "plugin.action.invoke",
        {
            "plugin_id": cfg["sidebar_plugin"],
            "action_id": cfg["dock_action"],
            "context": context,
        },
    )


def open_overlay(cfg: dict[str, Any]) -> str:
    result = api(
        "plugin.pane.open",
        {
            "plugin_id": cfg["sidebar_plugin"],
            "entrypoint": cfg["sidebar_entrypoint"],
            "placement": "overlay",
            "focus": True,
        },
    )
    try:
        return result["plugin_pane"]["pane"]["pane_id"]
    except (KeyError, TypeError) as error:
        raise ApiError(f"plugin.pane.open: no pane id in {result}") from error


def overlay_path() -> Path:
    return state_dir() / "overlays.json"


def load_overlays() -> dict[str, str]:
    path = overlay_path()
    try:
        data = json.loads(path.read_text())
        return {str(k): str(v) for k, v in data.items() if v}
    except (OSError, ValueError):
        return {}


def save_overlays(overlays: dict[str, str]) -> None:
    try:
        overlay_path().parent.mkdir(parents=True, exist_ok=True)
        overlay_path().write_text(json.dumps(overlays, indent=2) + "\n")
    except OSError:
        pass


def toggle_overlay(tab_id: str, cfg: dict[str, Any]) -> None:
    overlays = load_overlays()
    existing = overlays.pop(tab_id, "")
    if existing and try_close(existing, plugin_pane=True):
        save_overlays(overlays)
        return
    pane_id = open_overlay(cfg)
    overlays[tab_id] = pane_id
    save_overlays(overlays)


def close_overlay(tab_id: str) -> bool:
    overlays = load_overlays()
    existing = overlays.pop(tab_id, "")
    if not existing:
        return False
    save_overlays(overlays)
    return try_close(existing, plugin_pane=True)


def focused_tab_id(snap: dict[str, Any]) -> str:
    tab = str(snap.get("focused_tab_id") or "")
    if tab and tab in layouts_by_tab(snap):
        return tab
    env_tab = os.environ.get("HERDR_TAB_ID", "")
    if env_tab and env_tab in layouts_by_tab(snap):
        return env_tab
    return ""


def resolve_tab(snap: dict[str, Any]) -> str:
    """The tab a keypress acted on. The explicit toggle ignores context and
    uses herdr's focused tab, so prefer that; fall back to the env tab."""
    return focused_tab_id(snap)


def cmd_toggle() -> int:
    cfg = load_config()
    snap = snapshot()
    layouts = layouts_by_tab(snap)
    tab_id = resolve_tab(snap)
    if not tab_id or tab_id not in layouts:
        return 0
    layout = layouts[tab_id]
    width = int(layout.get("area", {}).get("width", 0))
    min_columns = int(cfg["min_columns"])
    if width < min_columns:
        # A docked pane from a wider client should not sit under the overlay.
        for pane_id in docked_sidebars(snap, layout, cfg):
            try_close(pane_id)
        toggle_overlay(tab_id, cfg)
    else:
        if close_overlay(tab_id):
            return 0
        before = {pane.get("pane_id") for pane in layout.get("panes", [])}
        open_dock(layout, cfg)
        focus_new_sidebar({pid for pid in before if pid}, tab_id, cfg)
    return 0


def log(message: str) -> None:
    try:
        path = state_dir() / "watcher.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} {message}\n")
    except OSError:
        pass


def trim_log(lines: int) -> None:
    try:
        path = state_dir() / "watcher.log"
        if not path.exists():
            return
        content = path.read_text(errors="replace").splitlines()
        if len(content) > lines:
            path.write_text("\n".join(content[-lines:]) + "\n")
    except OSError:
        pass


def watch() -> int:
    cfg = load_config()
    min_columns = int(cfg["min_columns"])
    poll = max(0.05, int(cfg["poll_ms"]) / 1000.0)
    retry = max(1.0, float(cfg["open_retry_seconds"]))
    last_width: dict[str, int] = {}
    last_focused = ""
    last_attempt: dict[str, float] = {}
    sidebar_hits: dict[str, int] = {}
    sentinel = object()
    failures = 0
    log(
        f"watcher start min_columns={min_columns} poll={poll:.2f}s "
        f"open_on_start={cfg['open_on_start']} open_on_focus={cfg['open_on_focus']}"
    )

    while True:
        try:
            snap = snapshot()
            failures = 0
        except (ApiError, OSError, ValueError) as error:
            failures += 1
            if failures == 1:
                log(f"snapshot failed: {error}")
            if failures >= 60:
                log("watcher stopping after 60 failed snapshots")
                return 0
            time.sleep(1.0)
            continue

        layouts = layouts_by_tab(snap)
        focused = focused_tab_id(snap)
        now = time.monotonic()
        first_pass = not last_width

        for tab_id, layout in layouts.items():
            width = int(layout.get("area", {}).get("width", 0))
            previous = last_width.get(tab_id, sentinel)
            moved = previous is not sentinel and previous != width
            crossed_up = previous is not sentinel and previous < min_columns <= width
            new_tab = previous is sentinel
            docked = docked_sidebars(snap, layout, cfg)

            if width < min_columns:
                if cfg["close_narrow"]:
                    # Two sightings (~one poll apart) let the toggle action
                    # record a just-opened overlay before it is considered
                    # docked. Do not close the only pane in a tab.
                    if len(layout.get("panes", [])) > 1:
                        for pane_id in docked:
                            hits = sidebar_hits.get(pane_id, 0) + 1
                            sidebar_hits[pane_id] = hits
                            if hits >= 2 and try_close(pane_id):
                                log(f"close {tab_id} {pane_id} at {width} cols")
            elif tab_id == focused and not docked:
                should_open = False
                why = ""
                if first_pass:
                    should_open = bool(cfg["open_on_start"])
                    why = "start"
                elif new_tab:
                    should_open = True
                    why = "new tab"
                elif crossed_up:
                    should_open = True
                    why = "resize"
                elif focused != last_focused and cfg["open_on_focus"]:
                    should_open = True
                    why = "focus"
                if should_open and now - last_attempt.get(tab_id, 0.0) >= retry:
                    last_attempt[tab_id] = now
                    try:
                        open_dock(layout, cfg)
                        log(f"open {tab_id} at {width} cols ({why})")
                    except (ApiError, OSError, ValueError) as error:
                        log(f"open {tab_id} failed: {error}")

            last_width[tab_id] = width

        if focused:
            last_focused = focused
        trim_log(int(cfg["log_lines"]))
        time.sleep(poll)


def pid_path() -> Path:
    return state_dir() / "watcher.pid"


def read_pid() -> int | None:
    try:
        return int(pid_path().read_text().strip())
    except (OSError, ValueError):
        return None


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def stop_watcher(quiet: bool = False) -> None:
    pid = read_pid()
    if pid and pid_alive(pid):
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    try:
        pid_path().unlink()
    except OSError:
        pass
    if not quiet:
        log("watcher stopped")


def cmd_stop() -> int:
    stop_watcher()
    return 0


def cmd_start() -> int:
    cfg = load_config()
    state_dir().mkdir(parents=True, exist_ok=True)
    # The startup hook runs once per server. A stale watcher from the previous
    # server cannot talk to the new socket; replace it rather than leaving two.
    stop_watcher(quiet=True)
    try:
        pid = os.fork()
    except OSError as error:
        print(f"fork failed: {error}", file=sys.stderr)
        return 1
    if pid > 0:
        return 0
    os.setsid()
    if os.fork() > 0:
        os._exit(0)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    try:
        sys.stdin.close()
    except OSError:
        pass
    log_path = state_dir() / "watcher.log"
    try:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text("")
    except OSError:
        pass
    try:
        fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
        os.dup2(fd, 1)
        os.dup2(fd, 2)
        if fd > 2:
            os.close(fd)
    except OSError:
        pass
    pid_path().write_text(str(os.getpid()) + "\n")
    try:
        watch()
    finally:
        try:
            pid_path().unlink()
        except OSError:
            pass
        os._exit(0)


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else "toggle"
    try:
        if command == "toggle":
            return cmd_toggle()
        if command == "start":
            return cmd_start()
        if command == "stop":
            return cmd_stop()
        if command == "watch":
            return watch()
        print(
            "usage: responsive_sidebar.py {toggle|start|stop|watch}",
            file=sys.stderr,
        )
        return 2
    except (ApiError, OSError, ValueError) as error:
        print(f"responsive-sidebar: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
