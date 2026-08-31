# AGENTS.md

## Project overview

`diffs.koplugin` is a KOReader plugin that displays the changes between two revisions of a public GitHub repository. It is written in Lua and runs inside KOReader's plugin environment.

## Repository layout

- `src/` — plugin implementation.
- `spec/` — tests and test doubles.
- `src/assets/` — bundled SVG assets used by the UI.
- `scripts/check.sh` — CI/local static-analysis entry point.
- `scripts/package.sh` — release archive builder.
- `.github/workflows/release.yml` — tag-based release workflow.
- `.luacheckrc` — Luacheck configuration.

## Development guidelines

- Keep the plugin compatible with KOReader's Lua version and APIs.
- Reuse KOReader UI primitives and utility modules instead of introducing external runtime dependencies.
- Keep responsibilities separated: parsing and GitHub requests belong in their dedicated modules; layout, state, preferences, and view interaction should remain in their respective modules.
- Preserve existing public module interfaces unless a change is required. Update corresponding specs when interfaces change.
- Prefer small, focused changes. Avoid unrelated formatting or refactoring.
- Use descriptive local names and follow the existing Lua style.
- Handle network and malformed-input failures explicitly; do not assume GitHub responses are always valid.
- Keep user-visible strings and UI behavior appropriate for KOReader's e-ink display and touch interaction.
- Do not commit generated release archives or credentials.

## Testing and checks

Run the repository check before submitting changes:

```bash
bash scripts/check.sh
```

The script runs Luacheck against both `src/` and `spec/` and exits nonzero for any warning or error. A successful run should report zero warnings and zero errors.

When changing behavior:

1. Add or update a focused spec under `spec/`.
2. Run the relevant spec while developing, if the local Busted setup is available.
3. Run `bash scripts/check.sh` before committing.
4. Review `git diff --check` and inspect the final diff.

Tests should not require a live GitHub request or a physical e-reader. Use deterministic fixtures and test doubles for network and KOReader services.

## Packaging and releases

Build a release archive with:

```bash
bash scripts/package.sh VERSION
```

`VERSION` should not include the leading `v`; the release workflow derives it from the pushed tag. Release tags use the `v*` pattern. Tags containing a hyphen are treated as beta/prerelease tags and must point to a commit reachable from `dev`. Stable releases should be created from the intended stable branch.

## Change checklist

- Confirm the change is limited to the requested behavior.
- Add regression coverage for changed logic or UI layout where practical.
- Document relevant user-visible or behavior changes in the `Unreleased` section of `CHANGELOG.md`.
- Run `bash scripts/check.sh`.
- Run `git diff --check`.
- Verify that packaging still includes the required plugin files.
- Summarize any KOReader-version or device-specific assumptions.
