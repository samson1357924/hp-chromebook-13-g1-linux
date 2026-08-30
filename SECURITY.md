<!-- markdownlint-disable MD013 -->
<!-- SPDX-License-Identifier: MIT -->
<!-- SPDX-FileCopyrightText: 2026 Samson <https://github.com/samson1357924> -->

# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| `main` (latest) | ✅ |

Only the `main` branch is supported. Fixes are provided via pull requests.

## Reporting a Vulnerability

If you discover a security vulnerability, please **do not** open a public issue.

Instead, use one of the following:

- **GitHub Private Reporting**: `Security` → `Report a vulnerability` on this repository (preferred, creates a private advisory).
- **Email**: contact the maintainer via GitHub profile (`https://github.com/samson1357924`).

Please include:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix if any

We will acknowledge receipt within **72 hours** and provide a fix timeline.

## Scope

This policy covers:

- Shell scripts under `scripts/`, `lib/`, `ec/`, `power/`, `audio/`, `keyboard/`
- GitHub Actions workflows under `.github/workflows/`
- AI bot code under `github_bot/`

Out of scope: upstream firmware (`MrChromebox`), kernel drivers (`i915`, `snd_soc_avs`), and third-party dependencies.

## Disclosure

Once a fix is merged, a GitHub Security Advisory will be published and credited (unless anonymity is requested).
