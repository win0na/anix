You have been iterating for a while. Check whether a wide, closed portion of history is now ready to fold.

Compress only when the span is large and clearly resolved: at least 20 messages or 20k removed tokens, ideally at least a fifth of the current context. Pick the widest safe range and batch independent ranges in a single call.

Do not compress the working set or a short tail of recent messages. If no span meets the floor, do not call compress; ignore this reminder and continue working.
