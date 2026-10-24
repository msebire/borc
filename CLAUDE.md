# CLAUDE.md

Repository conventions for Claude Code sessions.

- Line endings: LF everywhere, PowerShell files included (enforced by `.gitattributes`).
- Indentation: 2 spaces, no tabs.
- Encoding: UTF-8 with BOM for PowerShell files (`*.ps1`, `*.psm1`, `*.psd1`) so
  Windows PowerShell 5.1 reads them correctly; UTF-8 without BOM for everything else.
- Every file ends with a newline; trim trailing whitespace (except in Markdown).
- Never commit secrets: no tokens, passwords, keys or credentials, not even in examples.
