# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A Diffs settings screen for configuring a GitHub API key.
- An optional **View changes** button in ZenPM's GitHub-backed package menus, opening an editable comparison prefilled with the repository and installed/latest versions.

### Changed

- Store all Diffs settings in the local `Diffs/` directory and use `github_api.key` as the API key source of truth.

### Fixed

- Prevent comparison errors and empty comparisons from crashing KOReader when the API key existence flag shadows the translation function.
- Keep the GitHub API key settings dialog usable by avoiding a local variable that shadows the translation function.
- Load KOReader's bundled LuaFileSystem module so the plugin can start without a standalone `lfs` module.

## [1.0.0] - 2026-08-30

Initial release

[unreleased]: https://github.com/Saterz/diffs.koplugin/compare/v1.0.0...dev
[1.0.0]: https://github.com/Saterz/diffs.koplugin/releases/tag/v1.0.0
