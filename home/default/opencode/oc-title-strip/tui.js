import { Plugin } from "@opencode/plugin/tui"

// OpenCode's TUI titles the terminal `OC | <session>` before the title reaches
// the outer terminal, so Herdr and anything reading the title see the frame.
// The renderer's setTerminalTitle is the one place that title goes through.
const PREFIX = "OC | "

function strip(title) {
  return typeof title === "string" && title.startsWith(PREFIX)
    ? title.slice(PREFIX.length)
    : title
}

export default Plugin.define({
  id: "oc-title-strip",
  setup(context) {
    const { renderer, ui, data } = context
    const original = renderer.setTerminalTitle
    if (typeof original !== "function") return

    const patched = function (title) {
      return original.call(this, strip(title))
    }

    const hadOwn = Object.hasOwn(renderer, "setTerminalTitle")
    const own = renderer.setTerminalTitle
    try {
      Object.defineProperty(renderer, "setTerminalTitle", {
        configurable: true,
        writable: true,
        value: patched,
      })
    } catch {
      return
    }

    // The title already on screen was set before this plugin loaded; repeat
    // the session route's title once so it loses the frame immediately.
    try {
      const route = ui.router.current()
      const title =
        route?.type === "session" ? data.session.get(route.sessionID)?.title : undefined
      if (title) {
        const hostTitle = title.length > 40 ? `${title.slice(0, 37)}…` : title
        renderer.setTerminalTitle(`${PREFIX}${hostTitle}`)
      }
    } catch {}

    return () => {
      if (renderer.setTerminalTitle !== patched) return
      if (hadOwn) renderer.setTerminalTitle = own
      else delete renderer.setTerminalTitle
    }
  },
})
