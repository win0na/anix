// rootshell-notify managed extension v1 opencode sha256=04ac2781afaf0c4a69a7d342b6f037aa3fe47e39e9fbafc3b4a33e9d208ee181
// Uses only JavaScript syntax and Node built-ins; no OpenCode SDK imports.
// OpenCode loads this file directly from plugins/, so it must be a plain
// dependency-free module whose default export is the plugin definition.
// Completion delivery is synchronous: a one-shot `opencode run` may shut down
// immediately after session.execution.succeeded, before any session lookup.
import { spawn } from "node:child_process";

const AGENT = "opencode";
const REGISTRY = Symbol.for("rootshell-notify.push.opencode.v1");
const MAX_TEXT = 16_000;
const MAX_BLOCKS = 8;
const MAX_SESSIONS = 512;
const BLOCK_DELAY = 2000;

function text(value) {
  return typeof value === "string" ? value : "";
}

export default {
  id: "rootshell-push",
  setup(ctx) {
    // OpenCode can load both the personal and the project copy of this file.
    const owners = globalThis[REGISTRY] ??= new Map();
    const owner = {};
    const owned = new Set();
    const children = new Set();
    // Per session: { messageID, parts: Map<ordinal, text>, next }.
    const texts = new Map();
    // Per session: the assistant message ID of the current step.
    const steps = new Map();
    // Synchronous completion metadata, filled by events and background lookups.
    const locations = new Map();
    const lookedUp = new Set();
    const blocks = new Map();
    const controller = new AbortController();
    let closed = false;

    function debug(error) {
      if (process.env.ROOTSHELL_PUSH_DEBUG !== "1") return;
      try { console.error("rootshell-push:", error); } catch {}
    }

    function idOf(value) {
      return typeof value === "string" && value.length > 0 ? value : "";
    }

    function sessionOf(data, event) {
      return idOf(data.sessionID) || idOf(data.sessionId) || idOf(data.session_id) ||
        idOf(event.sessionID) || idOf(event.sessionId);
    }

    // Claiming is synchronous so two loaded copies cannot both send for one
    // session. The map is released on cleanup or session deletion.
    function claim(id) {
      const existing = owners.get(id);
      if (existing === owner) return true;
      if (existing) return false;
      owners.set(id, owner);
      owned.add(id);
      while (owners.size > MAX_SESSIONS) {
        let evicted = false;
        for (const key of owners.keys()) {
          if (owners.size <= MAX_SESSIONS) break;
          if (key === id || owners.get(key) === owner) continue;
          owners.delete(key);
          evicted = true;
        }
        if (!evicted) break;
      }
      return true;
    }

    function release(id) {
      if (owners.get(id) === owner) owners.delete(id);
      owned.delete(id);
    }

    async function sessionInfo(id) {
      try {
        const info = await ctx.session.get({ sessionID: id });
        return info && typeof info === "object" ? info : undefined;
      } catch (error) {
        // An already-disposed session must not fail the notification path.
        debug(error);
        return undefined;
      }
    }

    function isChild(id, info) {
      if (children.has(id)) return true;
      return info != null && info.parentID != null && info.parentID !== "";
    }

    function addChild(id) {
      children.add(id);
      if (children.size > 1024) children.delete(children.values().next().value);
    }

    function setLocation(id, directory) {
      if (typeof directory !== "string" || !directory) return;
      locations.set(id, directory);
      while (locations.size > MAX_SESSIONS) locations.delete(locations.keys().next().value);
    }

    // One-shot `opencode run` can emit location.shutdown right after a
    // completion, so session APIs may never answer. Look session info up in
    // the background at the first sign of an execution instead.
    function prefetch(id) {
      if (closed || !id || lookedUp.has(id)) return;
      lookedUp.add(id);
      while (lookedUp.size > MAX_SESSIONS) {
        const oldest = lookedUp.values().next().value;
        if (oldest === id) break;
        lookedUp.delete(oldest);
      }
      let pending;
      try {
        pending = ctx.session?.get?.({ sessionID: id });
      } catch (error) {
        debug(error);
        return;
      }
      Promise.resolve(pending).then((info) => {
        try {
          if (closed || !info || typeof info !== "object") return;
          setLocation(id, info.location?.directory);
          if (info.parentID != null && info.parentID !== "") addChild(id);
        } catch (error) {
          debug(error);
        }
      }, (error) => {
        debug(error);
      });
    }

    function cwdOf(id) {
      const directory = locations.get(id);
      if (typeof directory === "string" && directory) return directory;
      const local = ctx.location?.directory;
      return typeof local === "string" ? local : "";
    }

    function cachedText(id) {
      const entry = texts.get(id);
      if (!entry) return undefined;
      texts.delete(id);
      const keys = [...entry.parts.keys()].sort((left, right) => {
        const leftNumber = typeof left === "number";
        const rightNumber = typeof right === "number";
        if (leftNumber && rightNumber) return left - right;
        if (leftNumber) return -1;
        if (rightNumber) return 1;
        return 0;
      });
      let value = "";
      for (const key of keys) {
        const part = entry.parts.get(key);
        if (!part) continue;
        value += (value ? "\n" : "") + part;
        if (value.length >= MAX_TEXT) break;
      }
      return value.slice(0, MAX_TEXT);
    }

    function noteStep(id, messageID) {
      if (!messageID) return;
      steps.set(id, messageID);
      const entry = texts.get(id);
      if (!entry) {
        // An empty entry records that the new step has no text yet, so the
        // completion cannot fall back to a previous turn.
        texts.set(id, { messageID, parts: new Map(), next: 0 });
      } else if (!entry.messageID) {
        entry.messageID = messageID;
      } else if (entry.messageID !== messageID) {
        texts.set(id, { messageID, parts: new Map(), next: 0 });
      }
    }

    function partKey(entry, ordinal) {
      const value = Number(ordinal);
      if (ordinal !== null && ordinal !== undefined && ordinal !== "" && Number.isFinite(value)) {
        return value;
      }
      entry.next += 1;
      return `~${entry.next}`;
    }

    function eventID(event, data, id) {
      for (const value of [event.id, data.id, data.requestID, data.requestId,
        data.executionID, data.executionId, data.assistantMessageID, data.form?.id]) {
        if (typeof value === "string" && value) return value.slice(0, 256);
      }
      const created = data.created ?? event.created;
      if (created !== undefined && created !== null && created !== "") {
        const stamp = created instanceof Date ? created.getTime() : created;
        return `${event.type}:${id}:${stamp}`.slice(0, 256);
      }
      return `${event.type}:${id}:${Date.now()}`.slice(0, 256);
    }

    function send(payload) {
      if (closed) return;
      let child;
      try {
        child = spawn("rootshell-notify", ["hook", "--agent", AGENT], {
          detached: true, stdio: ["pipe", "ignore", "ignore"], windowsHide: true,
        });
      } catch (error) {
        debug(error);
        return;
      }
      try {
        // Nothing waits for the hook, so only error listeners are needed:
        // an unhandled ENOENT/EPIPE would otherwise take down OpenCode.
        child.on("error", () => {});
        child.stdin?.on("error", () => {});
        child.stdin?.end(JSON.stringify(payload));
        child.unref?.();
        child.stdin?.unref?.();
      } catch (error) {
        debug(error);
      }
    }

    function unblock(key) {
      const entry = blocks.get(key);
      if (!entry) return;
      clearTimeout(entry.timer);
      blocks.delete(key);
    }

    function unblockSession(id) {
      for (const entry of [...blocks.values()]) {
        if (entry.session === id) unblock(entry.key);
      }
    }

    function block(session, key, message, eventIDValue) {
      if (closed || !session || children.has(session) || blocks.has(key) ||
        blocks.size >= MAX_BLOCKS) return;
      const entry = { session, key, message: text(message).slice(0, MAX_TEXT), id: eventIDValue };
      blocks.set(key, entry);
      entry.timer = setTimeout(() => {
        entry.timer = undefined;
        fire(entry);
      }, BLOCK_DELAY);
      entry.timer.unref?.();
    }

    async function fire(entry) {
      try {
        if (closed || blocks.get(entry.key) !== entry) return;
        blocks.delete(entry.key);
        const info = await sessionInfo(entry.session);
        if (closed) return;
        if (info && typeof info === "object") {
          setLocation(entry.session, info.location?.directory);
          if (info.parentID != null && info.parentID !== "") addChild(entry.session);
        }
        if (isChild(entry.session, info)) return;
        if (!claim(entry.session)) return;
        send({
          hook_event_name: "input_required", session_id: entry.session,
          event_id: entry.id, cwd: cwdOf(entry.session), message: entry.message,
        });
      } catch (error) {
        debug(error);
      }
    }

    function resourceOf(resources) {
      if (!Array.isArray(resources)) return "";
      for (const resource of resources) {
        const value = typeof resource === "string" ? resource
          : idOf(resource?.path) || idOf(resource?.name) || idOf(resource?.title);
        if (value && value.length <= 200 && !/[\r\n]/.test(value)) return value;
      }
      return "";
    }

    function completion(id, eventIDValue, failed) {
      // One-shot `opencode run` may emit location.shutdown immediately after
      // these events, so everything needed for delivery must be local.
      unblockSession(id);
      const cached = cachedText(id);
      if (closed || children.has(id)) return;
      if (!claim(id)) return;
      send({
        hook_event_name: "agent_end", session_id: id, event_id: eventIDValue,
        cwd: cwdOf(id), stop_reason: failed ? "error" : "stop",
        last_assistant_message: (cached ?? "").slice(0, MAX_TEXT),
      });
    }

    function handle(event) {
      if (!event || typeof event.type !== "string") return;
      // Some event shapes carry `properties` instead of `data`.
      const data = event.data ?? event.properties ?? {};
      switch (event.type) {
        case "session.created": {
          const id = sessionOf(data, event);
          if (!id) return;
          setLocation(id, data.location?.directory);
          const parent = idOf(data.parentID) || idOf(data.parentId);
          if (parent) addChild(id);
          return;
        }
        case "session.deleted": {
          const id = sessionOf(data, event);
          if (!id) return;
          children.delete(id);
          texts.delete(id);
          steps.delete(id);
          locations.delete(id);
          lookedUp.delete(id);
          unblockSession(id);
          release(id);
          return;
        }
        case "session.execution.started": {
          const id = sessionOf(data, event);
          if (!id) return;
          // Text belongs to one execution; a retry must not reuse old text.
          texts.delete(id);
          steps.delete(id);
          unblockSession(id);
          prefetch(id);
          return;
        }
        case "session.step.started":
        case "session.step.ended": {
          const id = sessionOf(data, event);
          if (!id) return;
          noteStep(id, idOf(data.assistantMessageID));
          prefetch(id);
          return;
        }
        case "session.text.ended": {
          const id = sessionOf(data, event);
          if (!id) return;
          const value = text(data.text);
          if (!value) return;
          const messageID = idOf(data.assistantMessageID);
          const active = steps.get(id);
          // A part for a superseded assistant message must not extend or
          // replace the current step's body.
          if (messageID && active && active !== messageID) return;
          let entry = texts.get(id);
          if (!entry || (messageID && entry.messageID !== messageID)) {
            entry = { messageID: messageID || "", parts: new Map(), next: 0 };
            texts.set(id, entry);
          }
          entry.parts.set(partKey(entry, data.ordinal), value.slice(0, MAX_TEXT));
          prefetch(id);
          return;
        }
        case "session.execution.interrupted": {
          // Interruptions are not completions and must stay silent.
          const id = sessionOf(data, event);
          if (!id) return;
          texts.delete(id);
          steps.delete(id);
          unblockSession(id);
          return;
        }
        case "session.execution.succeeded":
        case "session.execution.failed": {
          const id = sessionOf(data, event);
          if (!id) return;
          return completion(id, eventID(event, data, id),
            event.type === "session.execution.failed");
        }
        case "permission.asked": {
          const id = sessionOf(data, event);
          if (!id) return;
          const request = idOf(data.id) || eventID(event, data, id);
          let message = text(data.message).trim();
          if (!message) {
            const action = text(data.action).trim();
            message = action ? `Waiting for approval: ${action}` : "Waiting for approval.";
            const resource = resourceOf(data.resources);
            if (resource) message += ` (${resource})`;
          }
          block(id, `permission:${request}`, message, request);
          return;
        }
        case "permission.replied": {
          const request = idOf(data.requestID) || idOf(data.requestId) || idOf(data.id);
          if (request) unblock(`permission:${request}`);
          return;
        }
        case "form.created": {
          const form = data.form && typeof data.form === "object" ? data.form : data;
          const id = idOf(form.sessionID) || idOf(form.sessionId) ||
            idOf(data.sessionID) || sessionOf(data, event);
          // Global forms are OpenCode configuration, not an agent blocker.
          if (!id || id === "global") return;
          // The form ID is the stable identity; replaying the same form must
          // hash to the same event. Envelope IDs only cover a missing form ID.
          const formID = idOf(form.id) || eventID(event, data, id);
          let message = text(form.title).trim();
          if (!message) {
            const field = Array.isArray(form.fields) ? form.fields[0] : undefined;
            message = idOf(field?.title) || idOf(field?.key);
          }
          block(id, `form:${formID}`, message || "OpenCode is asking you a question", formID);
          return;
        }
        case "form.replied":
        case "form.cancelled": {
          const formID = idOf(data.id) || idOf(data.form?.id);
          if (formID) unblock(`form:${formID}`);
          return;
        }
        default:
          return;
      }
    }

    function cleanup() {
      if (closed) return;
      closed = true;
      try { controller.abort(); } catch {}
      for (const entry of blocks.values()) clearTimeout(entry.timer);
      blocks.clear();
      texts.clear();
      steps.clear();
      locations.clear();
      lookedUp.clear();
      children.clear();
      for (const id of [...owned]) release(id);
      owned.clear();
    }

    let stream;
    try {
      stream = ctx.event?.subscribe?.({ signal: controller.signal });
    } catch (error) {
      debug(error);
    }
    if (stream) {
      (async () => {
        try {
          for await (const event of stream) {
            if (closed) break;
            try {
              // Await so a completion's async lookups cannot interleave with
              // a later execution.started or text event for the same session.
              await handle(event);
            } catch (error) {
              debug(error);
            }
          }
        } catch (error) {
          // Aborting the subscription is how this loop normally ends.
          debug(error);
        }
      })();
    }

    return cleanup;
  },
};
