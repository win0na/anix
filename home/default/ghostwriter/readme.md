# README profile

Selected bundle: A (Indie SwiftUI), 2026-11-06.

Provenance: house profile based on IceCubesApp (README), isowords (README),
Apple Food Truck (README), and Mastodon iOS (Documentation/Setup). House
profile, not a personal sample.

Models:
- IceCubesApp: feature-first README, screenshots, architecture note, build steps.
- isowords: architecture depth, Getting Started, technical curiosity.
- Apple Food Truck: overview, configure, step-by-step instructions.
- Mastodon iOS: a short README that routes setup to Documentation/Setup.md.

## Reader
Someone arriving from GitHub, a search result, or the App Store with fifteen
seconds and one question: what is this, will it run on my device, and how do I
build or install it? They are not a contributor. Build pipeline, workspace
layout, release process, and coding standards belong in CONTRIBUTING.md,
AGENTS.md, or docs/.

## Spine
1. Display name as `#`, with the app name in spaces and capitals.
2. One-line tagline: what it does, not the name. 8-16 words.
3. One real screenshot or a short demo GIF. Skip it if the UI is not ready.
4. A short status line only when it changes install: beta, sideload,
   device-only, or an App Store link.
5. `## Features`: 3-6 user-visible capabilities, one sentence each. Group with
   `###` only when a group has 3 or more bullets.
6. `## Requirements`: iOS/iPadOS version, device class, Xcode/Swift version,
   toolchain, and any external service. Exact versions.
7. `## Build`: clone, submodules, config file, one build command. One path, not
   a package-manager matrix.
8. `## Run`: simulator and device steps, signing, install. Numbered steps, one
   action each.
9. `## Architecture`: 2-4 sentences on the shape of the app; link to docs/ for
   detail. No module tree.
10. `## Docs`: links to the docs index and the most useful pages.
11. `## License`: bare license name. Credits only when required.

## Voice
Use the `soul.md` voice. Feature-first, screenshot-led, understated. The README
is a shop window, not a wiki.

## Rules
- Open with "iMC is ..." or "iMC runs ...", not "This project is ...".
- Feature bullets: `- **Name:** what it does.` or a verb-first sentence.
- Every code block runs as pasted; use real paths and values.
- Use fenced `sh` blocks for commands; show the expected result in a comment or
  the next sentence.
- Mention device-only behavior and known limitations before the reader hits them.
- Link to `docs/` instead of inlining long explanations.
- No badges unless the app is listed on a registry or the App Store; no CI,
  stars, downloads, or "maintained" badges.
- No "Contributing" section unless the repo accepts contributions; link to
  `CONTRIBUTING.md` if it exists.
- No fake screenshots, no mock UI, no placeholder text.
- Keep the README to 40-90 lines; a CLI with flag tables may reach 120.

## Anti-patterns
- "This project aims to..."
- "simple", "easy", "just", "works out of the box" unless verified.
- A package-manager matrix for one app.
- A `git clone` quickstart for a published app.
- Internal workspace layout, release process, or coding standards.
- A feature list that describes the code, not what the user can do.
- A screenshot that shows a different build or a mockup.

## Not me
- Marketing superlatives.
- Emoji, exclamation marks, em dashes.
- A README written for the maintainer.

## Edits
(empty; add the user's corrections here.)

## Excerpts
(no personal excerpts yet; add 2-3 redacted samples under 280 characters when
they exist.)
