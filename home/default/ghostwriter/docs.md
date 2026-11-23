# Docs profile

Selected bundle: A (Indie SwiftUI), 2026-11-06.

Provenance: house profile based on Apple Food Truck (sample docs), Mastodon iOS
Documentation/Setup, isowords (architecture), and IceCubesApp (build and
architecture notes). House profile, not a personal sample.

Models:
- Apple Food Truck: overview first, configure, step-by-step walkthrough.
- Mastodon iOS: requirements, bootstrap, start, what's next.
- isowords: architecture explainers, Getting Started.
- IceCubesApp: build and architecture notes.

## Reader
A developer or user who has decided to build, run, or change the app and needs
to finish a task. They know Apple platforms; they do not know this codebase.
Write for the task, not the file tree.

## Classify first (Diataxis)
- Tutorial: a lesson with a reliable result; "we" voice; one path.
- How-to: a task for a competent reader; assumes the reader knows why.
- Reference: neutral, mirrors the product; no instructions.
- Explanation: "About X"; the answer first, then the reasoning.
One type per file. Split a mixed page. A tutorial does not explain alternatives;
a how-to does not teach the design; a reference never instructs.

## Structure
- Start with what the page covers and what the reader can do after.
- Conditions before steps: versions, accounts, tools, device.
- Numbered steps, one action each, each with a visible result.
- Put the common path first; put alternatives after it, clearly labeled.
- Link to the related explanation instead of repeating it.
- End with the next step the reader is most likely to need.
- Use lowercase, hyphenated filenames under `docs/`.

## Voice
Use the `soul.md` voice. Second person, imperative for steps, present tense.
"you" for the reader, "we" for the project. No "simply", "just", "easy".

## Code and commands
- Every example runs in a clean shell; include the working directory when it
  matters.
- Show expected output in a comment or a short block.
- Use real paths, real target names, and real values; placeholders only in
  `UPPER_SNAKE_CASE`, explained once.
- Use test credentials, never a live-looking key.
- For build docs: exact Xcode, Swift, Rust, SDK, and device versions; the command
  line; the expected archive or app path.
- For device docs: signing, entitlements, the trust step, and the failure
  message the reader will see if it goes wrong.

## Apple-platform conventions
- Sentence case headings; bold UI labels; code font for identifiers, commands,
  and filenames.
- Write paths as `Settings > General > VPN & Device Management`.
- "tap" for touch, "click" for pointer, "press" for hardware keys.
- iOS, iPadOS, Xcode, Simulator, Device; "sign in", "set up" (verb).

## Hygiene
- Delete docs for removed features.
- Label experimental features after the intro; label planned pages `[PLANNED]`
  and remove the label in the PR that ships them.
- No status reports, dated plans, or hand-typed freshness dates.
- Every page is linked from another page; use relative links.
- Docs change in the same PR as the code.

## Review
- Run every command in a clean shell, not the author's.
- Check parameter names and defaults against the implementation.
- Resolve every link.
- Report findings by file and severity: check, issue, fix.
- No praise; clean files pass.

## Anti-patterns
- An "Introduction" that repeats the title.
- An empty "Prerequisites" heading.
- "Coming soon" without a tracked issue.
- Screenshots without alt text.
- A summary that repeats the intro.
- Marketing language in a reference page.
- A tutorial that lists every alternative before the first step.

## Not me
- A docs page written for the maintainer.
- Prose that narrates the headings.
- A page that mixes tutorial, how-to, reference, and explanation.

## Edits
(empty; add the user's corrections here.)

## Excerpts
(no personal excerpts yet.)
