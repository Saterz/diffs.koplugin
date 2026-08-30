# diffs.koplugin

A KOReader plugin for viewing the changes between two revisions of a public
GitHub repository.

## MVP features

- Compare commit SHAs, branches, or release tags through GitHub's compare API.
- Parse unified diffs into files, hunks, and numbered lines.
- Display combined diffs by default.
- Switch persistently between combined and split layouts in either orientation.
- Keep wrapping disabled by default and allow it to be toggled.
- Leave line-number gutters blank on wrapped continuation rows.
- Emphasize paired character changes within modified lines.
- Preserve unknown Git file headers and report malformed hunk counts as warnings.
- Remember the last comparison fields and viewer settings across restarts.
- Scrub quickly through diffs with an always-visible, touch-friendly e-ink
  scrollbar in its own right-side gutter.
- Identify additions and removals without relying on color:
  - additions use a light gray background and a `+` marker;
  - removals use a distinct, slightly stronger light gray and a `−` marker;
  - exact character changes use a stronger background while retaining black text.

## Installation

Copy this repository to KOReader's plugin directory and keep the `.koplugin`
suffix:

```text
koreader/plugins/diffs.koplugin/
```

Restart KOReader, open **Tools → Diffs**, and enter:

1. A repository owner such as `koreader`.
2. A repository name such as `koreader`.
3. A base commit, branch, or tag.
4. A head commit, branch, or tag.

The MVP uses GitHub's unauthenticated API and therefore supports public
repositories only. GitHub may temporarily reject requests after its anonymous
rate limit is reached.

## Viewer controls

The viewer title bar has two icon controls:

- **×** closes the viewer.
- **⚙** opens persistent settings for line wrapping and layout.

Swipe north or south to move by a page. With wrapping disabled, swipe west or
east to scroll long lines horizontally. Drag the scrollbar to scrub rapidly or
tap its rail to jump without dragging.

## Tests

The pure-Lua comparison model, diff parser, line pairing, intraline logic, and
scrollbar calculations have Busted specifications in `spec/`.

When this plugin is checked out inside a KOReader development tree, run the
plugin specifications with KOReader's Busted environment and include the
plugin root in `LUA_PATH` so modules such as `diff_parser` resolve correctly.

## MVP limits

- Git combined-merge diffs are not supported.
- Git binary patch payloads are identified but not decoded.
- Syntax highlighting and user-configurable themes are intentionally deferred.
