Before compressing, size the opportunity.

Compress only if a wide, closed span has accumulated since your last compression: at least 20 messages or 20k removed tokens, ideally at least a fifth of the current context. Prefer the widest safe range and batch independent ranges in one call.

If no span meets that floor, do not call compress. Ignore this reminder and continue working - a compression that saves little costs more than it saves.
