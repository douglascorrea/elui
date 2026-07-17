# Changelog

All notable changes to Elui will be documented in this file.

The format is inspired by Keep a Changelog, and this project uses semantic
versioning once published.

## Unreleased

### Added

- `Elui.Theme` with semantic roles and built-in `dark`, `light`, and
  `high-contrast` palettes, plus truecolor `opencode`, `tokyonight`, and
  `catppuccin` palettes.
- `Elui.Widgets.Modal`, `FilterableSelect`, and `TextArea` for compact,
  app-owned editing workflows.
- Opt-in word wrapping for `Elui.Widgets.TextArea`, including wrapped cursor
  placement, visual-row scrolling, and safe oversized-token wrapping.
- `Elui.Widgets.ToggleGrid` for cell-focused boolean matrices with
  optional per-row actions and an add-row control.
- `Elui.Widgets.WeekGrid` for seven-day schedule layouts, including a
  `fits?/2` seam for responsive fallbacks.
- Ratatui-inspired terminal rendering primitives for buffers, frames, styles,
  layout, widgets, and test backends.
- `Elui.App`, an Elm-style runner for keyboard, mouse, tick, resize, and
  process-message events.
- Example applications ported from Ratatui's `examples/apps/` directory.
- BEAM Lab example showing supervisors, GenServers, BEAM node discovery,
  remote-node connection, and streamed GitHub events.
- Open-source project files: README, license, contributing guide, security
  policy, support guide, code of conduct, issue templates, PR template, and CI.
- Static project website under `website/`, including a GitHub Pages workflow
  and `elui.sh` custom-domain file.

### Fixed

- Text and block borders now preserve inherited cell attributes that their
  local styles do not override, enabling reliable full-viewport themes.
- Visible `Paragraph` glyphs now inherit the widget's base style while more
  specific text, line, and span styles continue to override it.
- Raw terminal mode now disables software flow control so Ctrl shortcuts reach
  applications and restores the original terminal state on exit.
- Empty `TextArea` placeholders retain their first grapheme under the cursor.

### Security

- The BEAM Lab example now generates a per-run distributed Erlang cookie by
  default.
- The example hyperlink widget strips injected terminal control characters
  from link labels and URLs before wrapping them in OSC 8 sequences.
