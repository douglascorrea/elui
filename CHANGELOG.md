# Changelog

All notable changes to Elui will be documented in this file.

The format is inspired by Keep a Changelog, and this project uses semantic
versioning once published.

## Unreleased

### Added

- Ratatui-inspired terminal rendering primitives for buffers, frames, styles,
  layout, widgets, and test backends.
- `Elui.App`, an Elm-style runner for keyboard, mouse, tick, resize, and
  process-message events.
- Example applications ported from Ratatui's `examples/apps/` directory.
- BEAM Lab example showing supervisors, GenServers, BEAM node discovery,
  remote-node connection, and streamed GitHub events.
- Open-source project files: README, license, contributing guide, security
  policy, support guide, code of conduct, issue templates, PR template, and CI.

### Security

- The BEAM Lab example now generates a per-run distributed Erlang cookie by
  default.
- The example hyperlink widget strips injected terminal control characters
  from link labels and URLs before wrapping them in OSC 8 sequences.
