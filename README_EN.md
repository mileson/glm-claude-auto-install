# glm-claude-auto-install

> One-click installers for GLM Coding Plan + Claude Code and OpenAI Codex CLI on macOS and Windows.

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)
[![macOS](https://img.shields.io/badge/macOS-supported-black?logo=apple)](./scripts/macos)
[![Windows](https://img.shields.io/badge/Windows-supported-blue?logo=windows)](./scripts/windows)
[![Codex CLI](https://img.shields.io/badge/Codex%20CLI-OpenAI-412991)](https://developers.openai.com/codex/cli)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-GLM%20helper-orange)](https://docs.bigmodel.cn/cn/coding-plan/quick-start)

[简体中文](./README.md)

## What this project does

This repository packages beginner-friendly installers for two common onboarding tasks:

- Install **GLM Coding Plan + Claude Code** with automatic Node.js detection and setup.
- Install **OpenAI Codex CLI** with automatic Node.js detection and guided proxy/API-key configuration.

The scripts are built for users who do **not** already have a complete Node.js environment.

## Features

- Detects whether `node`, `npm`, and `npx` are ready.
- Installs **system-level Node.js** when the machine is missing a usable runtime.
- Installs CLI tools globally so users can run them directly from Terminal / PowerShell.
- Guides users through API key and endpoint configuration.
- Backs up existing local config files before overwriting them.
- Includes cleanup scripts for removing the old managed GLM Node runtime.
- Provides separate macOS and Windows entry points.

## Supported tools

### GLM Coding Plan + Claude Code

- Claude Code installer for GLM Coding Plan China / Global.
- Detects missing Node.js and installs it automatically.
- Writes user config for `coding-helper`, `~/.claude/settings.json`, and `~/.claude.json`.

### OpenAI Codex CLI

- Installs `@openai/codex` with npm.
- Guides the user to input a custom Base URL, API key, model, and reasoning effort.
- Writes `~/.codex/config.toml` and `~/.codex/auth.json`.
- Intended for users who run Codex through an OpenAI-compatible gateway.

## Project structure

```text
scripts/
  macos/
    install-glm-claude.command
    cleanup-old-glm-managed-install.command
    install-openai-codex.command
  windows/
    install-glm-claude.bat
    install-glm-claude.ps1
    cleanup-old-glm-managed-install.bat
    cleanup-old-glm-managed-install.ps1
    install-openai-codex.bat
    install-openai-codex.ps1

docs/releases/
  v0.1.0.md
```

## Quick Start

If you download from GitHub Releases, prefer the assets whose names include:

- `Double-Click.command` for macOS
- `Download-Then-Double-Click.zip` for Windows

GitHub applies filename compatibility rules to uploaded assets, so the Chinese `【双击执行】` wording is stored mainly in the asset label.

The Windows zip bundle already includes both the clickable `.bat` launcher and the underlying `.ps1` file, so one download is enough.

### Why do releases still show Source code (zip / tar.gz)

Those are auto-generated source archives provided by GitHub, not manually uploaded installer files.

If you only want the beginner-friendly installer, choose the assets whose names contain:

- `Double-Click`
- `Download-Then-Double-Click`

### macOS

#### Install GLM Coding Plan + Claude Code

```bash
chmod +x ./scripts/macos/install-glm-claude.command
./scripts/macos/install-glm-claude.command
```

#### Install OpenAI Codex CLI

```bash
chmod +x ./scripts/macos/install-openai-codex.command
./scripts/macos/install-openai-codex.command
```

### Windows

#### Install GLM Coding Plan + Claude Code

Double-click:

```text
scripts\windows\install-glm-claude.bat
```

#### Install OpenAI Codex CLI

Double-click:

```text
scripts\windows\install-openai-codex.bat
```

## Cleanup

If you previously used the older managed GLM Node runtime, run the cleanup entry after system-level installation succeeds.

### macOS

```bash
chmod +x ./scripts/macos/cleanup-old-glm-managed-install.command
./scripts/macos/cleanup-old-glm-managed-install.command
```

### Windows

Double-click:

```text
scripts\windows\cleanup-old-glm-managed-install.bat
```

## Notes

- The GLM installer is based on the official Coding Tool Helper flow and Node.js official distribution packages.
- The Codex installer follows the official Codex CLI npm installation path and uses a local file-based config/auth setup.
- Windows support for Codex CLI should be treated as **experimental**; WSL2 is still the safest path for daily use.
- The Codex auth file format used here is based on a working local Codex setup plus the official Codex config model-provider rules.

## Security

- Never commit real API keys.
- The scripts back up existing config before writing new files.
- Generated `~/.codex/auth.json`, `~/.chelper/config.yaml`, and Claude settings should stay local.
- If you discover a security issue, please follow [SECURITY.md](./SECURITY.md).

## Release notes

- [v0.1.0](./docs/releases/v0.1.0.md)

## References

- [GLM Coding Plan quick start](https://docs.bigmodel.cn/cn/coding-plan/quick-start)
- [GLM docs index](https://docs.bigmodel.cn/llms.txt)
- [OpenAI Codex CLI docs](https://developers.openai.com/codex/cli)
- [OpenAI Codex authentication docs](https://developers.openai.com/codex/auth)
- [Node.js downloads](https://nodejs.org/dist/)

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

MIT License. See [LICENSE](./LICENSE).

## Author
- X: [Mileson07](https://x.com/Mileson07)
- Xiaohongshu: [超级峰](https://xhslink.com/m/4LnJ9aB1f97)
- Douyin: [超级峰](https://v.douyin.com/rH645q7trd8/)
