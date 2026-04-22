# glm-claude-auto-install

> 面向 macOS 和 Windows 的一键安装脚本集合：帮助用户快速安装 GLM Coding Plan + Claude Code，以及 OpenAI Codex CLI。

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)
[![macOS](https://img.shields.io/badge/macOS-supported-black?logo=apple)](./scripts/macos)
[![Windows](https://img.shields.io/badge/Windows-supported-blue?logo=windows)](./scripts/windows)
[![Codex CLI](https://img.shields.io/badge/Codex%20CLI-OpenAI-412991)](https://developers.openai.com/codex/cli)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-GLM%20helper-orange)](https://docs.bigmodel.cn/cn/coding-plan/quick-start)

[English](./README_EN.md)

## 这个项目能做什么

这个仓库主要解决两类“新手首次安装”问题：

- 自动安装 **GLM Coding Plan + Claude Code**。
- 自动安装 **OpenAI Codex CLI**，并引导用户填写代理地址和 API Key。

如果用户电脑上没有完整的 Node.js 环境，脚本会先自动补齐，再继续安装 CLI 工具。

## 功能亮点

- 自动检测 `node`、`npm`、`npx` 是否可用。
- 缺失时自动安装**系统级 Node.js**。
- 将 CLI 工具安装为全局命令，方便直接使用。
- 引导用户输入 API Key、Base URL、模型等必要配置。
- 改写配置前自动备份旧文件。
- 提供旧版 GLM 本地托管 Node 环境的清理脚本。
- 同时提供 macOS 与 Windows 入口。

## 支持的安装器

### 1. GLM Coding Plan + Claude Code

适合需要把 GLM 编码套餐接入 Claude Code 的用户：

- 自动检测并安装 Node.js
- 自动安装 Claude Code 与 Coding Helper
- 自动写入 `coding-helper`、`~/.claude/settings.json`、`~/.claude.json`

### 2. OpenAI Codex CLI

适合需要通过自定义网关或兼容代理使用 Codex CLI 的用户：

- 自动安装 `@openai/codex`
- 引导输入 Base URL、API Key、模型与 reasoning effort
- 自动写入 `~/.codex/config.toml` 与 `~/.codex/auth.json`

## 项目结构

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

## 快速开始

如果你是从 GitHub Releases 下载，优先选择这些后缀的文件：

- `【双击执行】.command`：适用于 macOS
- `【下载后双击执行】.zip`：适用于 Windows

Windows 的 zip 压缩包里已经包含了可双击的 `.bat` 启动文件和底层 `.ps1` 脚本，用户只需要下载一个文件即可。

### Release 里为什么还有 Source code (zip / tar.gz)

这是 GitHub 自动附带的源码归档，不是我额外上传的安装文件。

如果你只是想直接运行安装器，请优先下载带有：

- `【双击执行】`
- `【下载后双击执行】`

这些后缀的文件。

### macOS

#### 安装 GLM Coding Plan + Claude Code

```bash
chmod +x ./scripts/macos/install-glm-claude.command
./scripts/macos/install-glm-claude.command
```

#### 安装 OpenAI Codex CLI

```bash
chmod +x ./scripts/macos/install-openai-codex.command
./scripts/macos/install-openai-codex.command
```

### Windows

#### 安装 GLM Coding Plan + Claude Code

直接双击：

```text
scripts\windows\install-glm-claude.bat
```

#### 安装 OpenAI Codex CLI

直接双击：

```text
scripts\windows\install-openai-codex.bat
```

## 清理旧版 GLM 本地托管环境

如果用户以前使用过旧版本地托管 Node 方案，可以在系统级安装成功后再运行清理脚本。

### macOS

```bash
chmod +x ./scripts/macos/cleanup-old-glm-managed-install.command
./scripts/macos/cleanup-old-glm-managed-install.command
```

### Windows

直接双击：

```text
scripts\windows\cleanup-old-glm-managed-install.bat
```

## 使用说明

- GLM 安装脚本基于官方 Coding Tool Helper 流程和 Node.js 官方安装包。
- Codex 安装脚本采用官方 npm 安装路径，并自动落本地配置文件。
- Codex CLI 在 Windows 上目前更适合作为**实验性方案**使用，长期使用仍建议 WSL2。
- Codex 的 `auth.json` 写法来自本地可用配置与官方文档中的 provider 配置规则组合验证。

## 安全说明

- 不要把真实 API Key 提交到仓库。
- 脚本写入新配置前会先备份旧文件。
- `~/.codex/auth.json`、`~/.chelper/config.yaml`、Claude 配置文件都应只保留在本地。
- 如发现安全问题，请参考 [SECURITY.md](./SECURITY.md)。

## 版本说明

- [v0.1.0](./docs/releases/v0.1.0.md)

## 参考资料

- [GLM Coding Plan 快速开始](https://docs.bigmodel.cn/cn/coding-plan/quick-start)
- [GLM 文档索引](https://docs.bigmodel.cn/llms.txt)
- [OpenAI Codex CLI 文档](https://developers.openai.com/codex/cli)
- [OpenAI Codex 鉴权文档](https://developers.openai.com/codex/auth)
- [Node.js 下载目录](https://nodejs.org/dist/)

## 贡献

请查看 [CONTRIBUTING.md](./CONTRIBUTING.md)。

## 许可证

MIT License，见 [LICENSE](./LICENSE)。

## 作者
- X: [Mileson07](https://x.com/Mileson07)
- 小红书: [超级峰](https://xhslink.com/m/4LnJ9aB1f97)
- 抖音: [超级峰](https://v.douyin.com/rH645q7trd8/)
