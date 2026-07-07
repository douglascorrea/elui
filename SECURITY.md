# Security Policy

## Supported Versions

Elui is pre-1.0. Security fixes are applied to the `master` branch until a
versioned support policy is published.

## Reporting A Vulnerability

Please do not open a public issue for security reports.

Use GitHub private vulnerability reporting if it is enabled for the repository.
If private reporting is unavailable, email `me@douglascorrea.io` with:

- A short description of the issue
- Steps to reproduce or proof-of-concept details
- Impact and affected versions or commits, if known
- Any suggested fix or mitigation

You should receive an initial response within 14 days.

## Security Notes For Terminal UIs

Elui writes to terminals. Terminals interpret control sequences, including ANSI,
CSI, and OSC sequences. Treat untrusted terminal output as a security boundary:

- Prefer normal Elui text and widget APIs for user-visible strings.
- Sanitize or reject untrusted raw escape/control sequences.
- Avoid embedding secrets in terminal output, logs, screenshots, or examples.
- Be careful with OSC 8 hyperlinks, clipboard-related OSC sequences, title
  changes, and terminal modes.

## Security Notes For BEAM Distribution

Some examples demonstrate distributed Erlang. BEAM distribution is powerful and
should be treated as trusted infrastructure:

- Use unique cookies and do not commit real cookies to the repository.
- Connect only to nodes and networks you trust.
- Avoid exposing distributed nodes directly to untrusted networks.
- Prefer short-lived demo cookies for examples and local experiments.
