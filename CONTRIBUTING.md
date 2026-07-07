# Contributing To Elui

Thanks for taking the time to improve Elui.

## Before You Start

- For small fixes, open a pull request directly.
- For larger features, open an issue first so the design can be discussed.
- For security issues, do not open a public issue. Follow [SECURITY.md](SECURITY.md).

## Local Setup

```sh
mix deps.get
mix test
```

Useful checks before opening a pull request:

```sh
mix format --check-formatted
mix test
mix hex.audit
mix hex.build --unpack
```

## Development Notes

- Keep the public API close to the existing Ratatui-inspired vocabulary unless
  there is a clear Elixir or OTP reason to diverge.
- Prefer small, composable widgets and data structures over hidden process
  state.
- Use `Elui.Backend.Test` for rendering assertions.
- Example scripts should remain loadable with `ELUI_SKIP_EXAMPLE_RUN=1`.
- When adding terminal output helpers, be careful with ANSI, CSI, OSC, ESC, and
  BEL control sequences. Untrusted strings should not be able to inject
  terminal control syntax unless the API explicitly documents that behavior.

## Pull Request Checklist

- Tests pass locally.
- Formatting passes locally.
- Public behavior changes are covered by tests or an example.
- New public APIs include `@moduledoc`, `@doc`, or a clear reason not to.
- User-facing documentation is updated when behavior changes.
- Existing tests were not weakened to make a regression pass.

## Release Notes

When a change is user-visible, add an entry to `CHANGELOG.md` under
`Unreleased`.
