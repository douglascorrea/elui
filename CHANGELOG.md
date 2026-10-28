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
- `Elui.Fuzzy`, an fzf-style matcher (characters in order, every word,
  smart case, best match first), ported from vibex's `vibex pick`.
- `FilterableSelect` options: `matcher: :fuzzy` (`Elui.Fuzzy` ranking),
  `create: true` (a `+ create "TEXT"` row when the filter names no item,
  answered as `{:create, text}`; label set by `:create_label`), and
  `:match_style` for the matched characters. `State.matches/1` returns each
  item with its matched byte offsets.
- `Elui.Widgets.Tree`, a tree of foldable items (like `tui-tree-widget`, but
  starting expanded): selection by id that survives the tree being rebuilt,
  Left/Right folding, paging, optional wrapping of long labels, `hit/4` for
  mouse clicks on rows and fold markers, `label_area/4` for inline editors,
  and `prune/2` for filtering with ancestors kept.
- `Elui.Widgets.DatePicker`, a month calendar with a cursor (arrows move a
  day or a week, Page Up/Down a month) and a line for typed dates that the
  calendar follows: ISO dates, `today`, `tomorrow`, weekdays, `next week`,
  `next month`, `+3d`/`-1w`/`2m`/`1y`, `nov 15`, and a day of the month.
  `DatePicker.parse/2` is usable on its own; `DatePicker.size/1` sizes its
  modal.
- `Elui.Widgets.TextInput`, a one-line text field: a prompt, a placeholder
  while empty, a reversed cursor cell, and sideways scrolling that keeps the
  cursor in view without splitting wide characters. Editing works by grapheme,
  with readline and macOS keys (Ctrl-A/E/B/F/H/D/W/U/K, Alt-B/F/D,
  Alt/Ctrl+Left/Right, Alt-Backspace); Enter submits and Esc cancels.
  `TextInput.cursor_position/3` gives the cell for the terminal's own cursor.
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
- Complete Open Graph and X/Twitter social-card metadata for `elui.sh`, with a
  1200-by-630 project preview image.
- Privacy-conscious PostHog analytics for website visits, referrals, Web
  Vitals, navigation, examples, outbound links, scroll depth, and engagement.

### Fixed

- `Tree`'s `highlight_style` is drawn over the selected row, as ratatui's
  `List` does: its colours win over the label's own and its modifiers add to
  them. Before, a label coloured like the highlight's background (an
  accent-coloured title on an accent highlight) vanished on the selected row.
- Text and block borders now preserve inherited cell attributes that their
  local styles do not override, enabling reliable full-viewport themes.
- Visible `Paragraph` glyphs now inherit the widget's base style while more
  specific text, line, and span styles continue to override it.
- Raw terminal mode now disables software flow control so Ctrl shortcuts reach
  applications and restores the original terminal state on exit.
- Empty `TextArea` placeholders retain their first grapheme under the cursor.
- `FilterableSelect` lets `j` and `k` be typed into the filter; the selection
  moves with Up/Down, Ctrl-N/Ctrl-P, or Ctrl-J/Ctrl-K, and characters typed
  with Ctrl or Alt no longer go into the filter. The substring matcher
  ignores the filter's surrounding spaces.

### Security

- The BEAM Lab example now generates a per-run distributed Erlang cookie by
  default.
- The example hyperlink widget strips injected terminal control characters
  from link labels and URLs before wrapping them in OSC 8 sequences.
