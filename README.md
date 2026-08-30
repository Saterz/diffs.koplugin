# diffs.koplugin

A KOReader plugin for viewing the changes between two revisions of a public
GitHub repository.

## MVP features

- Compare commit SHAs, branches, or release tags through GitHub's compare API.
- Parse unified diffs into files, hunks, and numbered lines.
- Display combined diffs by default in portrait orientation.
- Always display split diffs in landscape orientation.
- Switch between combined and split layouts manually while in portrait.
- Keep wrapping disabled by default and allow it to be toggled.
- Emphasize paired character changes within modified lines.
- Preserve unknown Git file headers and report malformed hunk counts as warnings.
- Identify additions and removals without relying on color:
  - additions use a light gray background, a `+` marker, and a top rule;
  - removals use a darker gray background, a `−` marker, and a bottom rule;
  - intraline changes use a stronger shade of their line's background.

## Installation

Copy this repository to KOReader's plugin directory and keep the `.koplugin`
suffix:

```text
koreader/plugins/diffs.koplugin/
```

Restart KOReader, open **Tools → Diffs**, and enter:

1. A repository URL such as `https://github.com/koreader/koreader`.
2. A base commit, branch, or tag.
3. A head commit, branch, or tag.

The MVP uses GitHub's unauthenticated API and therefore supports public
repositories only. GitHub may temporarily reject requests after its anonymous
rate limit is reached.

## Viewer controls

The viewer title bar is divided into three touch targets:

- **Close** closes the viewer.
- **Combined/Split** changes the layout in portrait orientation. Landscape is
  always split.
- **Wrap: on/off** toggles line wrapping.

Swipe north or south to move by a page. With wrapping disabled, swipe west or
east to scroll long lines horizontally.

## Tests

The pure-Lua comparison model, diff parser, line pairing, and intraline logic
have Busted specifications in `spec/`.

When this plugin is checked out inside a KOReader development tree, run the
plugin specifications with KOReader's Busted environment and include the
plugin root in `LUA_PATH` so modules such as `diff_parser` resolve correctly.

## MVP limits

- Git combined-merge diffs are not supported.
- Git binary patch payloads are identified but not decoded.
- Syntax highlighting and user-configurable themes are intentionally deferred.
