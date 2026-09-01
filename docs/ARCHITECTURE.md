# Architecture

`diffs.koplugin` is a small KOReader plugin with a pipeline that turns a GitHub comparison into an interactive, touch-friendly diff viewer.

## Runtime flow

```text
KOReader Tools menu
        |
        v
src/main.lua
        |  collect and validate repository fields
        v
src/compare_request.lua
        |  normalized owner, repository, and revisions
        v
src/github_client.lua
        |  comparison metadata, then unified diff text
        v
src/diff_parser.lua
        |  files, hunks, lines, and warnings
        v
src/diff_view.lua
        |
        +--> src/diff_layout.lua       combined/split row layout
        +--> src/diff_view_state.lua   viewport and scroll state
        +--> src/diff_scrollbar.lua    scrollbar geometry and gestures
        +--> src/diff_settings.lua     viewer settings screen
        +--> src/diff_preferences.lua  persisted viewer preferences
```

## Main modules

| Module | Responsibility |
| --- | --- |
| `main.lua` | Registers the Tools submenu, opens the comparison and token settings forms, manages KOReader UI updates, and persists settings. |
| `compare_request.lua` | Trims and validates repository and revision fields before a request is made. |
| `github_client.lua` | Calls GitHub's public compare API, decodes comparison metadata, and downloads the unified diff. |
| `diff_parser.lua` | Parses unified diffs into files, hunks, numbered lines, file metadata, and parser warnings. |
| `diff_layout.lua` | Builds logical combined or split rows from parsed file hunks. |
| `diff_view.lua` | Renders the header, metadata, code rows, line numbers, and scrollbar, and handles viewer gestures. |
| `diff_view_state.lua` | Calculates gutters, panes, viewport dimensions, and layout-independent scroll progress. |
| `diff_scrollbar.lua` | Calculates the visible scrollbar and maps touch positions to diff rows. |
| `diff_settings.lua` | Displays the settings screen and changes wrapping and layout preferences. |
| `diff_preferences.lua` | Loads, normalizes, migrates, and stores viewer preferences. |
| `diff_icon.lua` | Loads and paints the bundled SVG controls. |
| `intraline.lua` | Identifies paired character-level changes within modified lines. |

## Data flow

The comparison form is converted into a normalized request:

```lua
{
    owner = "koreader",
    repo = "koreader",
    base_ref = "v2024.01",
    head_ref = "master",
}
```

`GitHubClient.compare` returns the unified diff and comparison metadata. The metadata includes the comparison status, ahead/behind counts, total commits, and the comparison URL.

`DiffParser.parse` returns a patch object with `files` and `warnings` arrays. Each file contains paths, status, raw headers, unknown headers, additions, deletions, and hunks. Each hunk contains old/new ranges and parsed context, addition, and deletion lines.

## UI and persistence

- `main.lua` registers the plugin in KOReader's Tools menu with **Compare** and nested **Settings → GitHub API key** entries.
- KOReader's `MultiInputDialog` collects repository/revision fields for comparisons and key input from the GitHub API key screen.
- GitHub work is scheduled through KOReader's UI manager after a loading message is displayed.
- General Diffs settings are stored in `Diffs/settings.lua`; the API key is stored in `Diffs/github_api.key`.
- The default layout is combined, and line wrapping is disabled by default.
- `diff_view.lua` renders the diff using KOReader's framebuffer and text-rendering APIs.
- `diff_settings.lua` provides touch-based controls for wrapping and combined/split layout.

## Network behavior

The plugin settings form can include an optional GitHub API token. The plugin sends it as a Bearer token with both requests; it is stored locally in KOReader's `diffs.lua` settings file. Without a token, the plugin uses GitHub's unauthenticated API and supports public repositories only. A comparison involves:

1. A JSON request to GitHub's compare endpoint.
2. A second request to the `diff_url` returned by the comparison response.

Transport failures, non-success HTTP statuses, invalid JSON, missing diff URLs, and malformed diff content are converted into user-visible errors or parser warnings.

## Tests

Specs in `spec/` cover request validation, parsing, layouts, preferences, scrollbar calculations, viewer gestures, viewer state, and GitHub client behavior. Tests should remain deterministic and should not require a live GitHub request or a physical e-reader.

## Packaging boundary

`scripts/package.sh` packages Lua files from `src/`, SVG assets, `README.md`, and `LICENSE`. Files under `docs/` and repository development files are documentation for maintainers and are not included in the installed plugin archive.