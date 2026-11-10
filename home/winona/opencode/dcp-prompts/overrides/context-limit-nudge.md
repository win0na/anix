CRITICAL WARNING: MAX CONTEXT LIMIT REACHED

You are at or beyond the configured soft max context threshold.

Use the `compress` tool only if a range of at least 20 messages or 20k removed tokens is closed and safe to fold. Do not compress a short recent tail or the active working set just to satisfy this warning. If no range meets the floor, do not call `compress`; continue working and let the soft limit be exceeded until a phase boundary.

SELECTION PROCESS
Start from older, resolved history and capture as much stale context as safely possible in one pass. Avoid the newest active working messages unless it is clearly closed. Prefer one wide range over several small ones.

SUMMARY REQUIREMENTS
Your summary MUST cover all essential details from the selected messages so work can continue. If the compressed range includes user messages, preserve user intent exactly. Prefer direct quotes for short user messages to avoid semantic drift. Do not produce a near-duplicate of an existing active summary.

Do not re-compress an active summary on its own. Include a compressed block only when the range also folds in substantial new raw history around it.
