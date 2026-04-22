# glm-claude-auto-install

> 给新手准备的一键安装工具页：按步骤下载、双击、输入信息，就能完成安装。

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)
[![macOS](https://img.shields.io/badge/macOS-supported-black?logo=apple)](./scripts/macos)
[![Windows](https://img.shields.io/badge/Windows-supported-blue?logo=windows)](./scripts/windows)
[![Codex CLI](https://img.shields.io/badge/Codex%20CLI-OpenAI-412991)](https://developers.openai.com/codex/cli)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-GLM%20helper-orange)](https://docs.bigmodel.cn/cn/coding-plan/quick-start)

[English](./README_EN.md)

## 先看这里

这个仓库一共提供两类一键安装器：

1. **GLM Coding Plan + Claude Code**
2. **OpenAI Codex CLI**

如果你的电脑里还没有完整的 Node.js，安装器会先自动补齐，再继续安装。

---

## 新手只要 3 步

### 第 1 步：先确认你要装哪个

#### 我要装 GLM Coding Plan + Claude Code

适合：

- 你要用智谱的 Coding Plan
- 你要把套餐接到 Claude Code

#### 我要装 OpenAI Codex CLI

适合：

- 你要安装 Codex 命令行工具
- 你有单独提供给用户的 Base URL 和 API Key

---

### 第 2 步：按你的系统点击下载

## 快速开始

### 安装 GLM Coding Plan + Claude Code

| 系统 | 下载 |
|---|---|
| macOS | [下载：GLM Claude 安装器（双击执行）](https://github.com/mileson/glm-claude-auto-install/releases/latest/download/GLM-Claude-macOS-Double-Click.command) |
| Windows | [下载：GLM Claude 安装器（下载后双击执行）](https://github.com/mileson/glm-claude-auto-install/releases/latest/download/GLM-Claude-Windows-Download-Then-Double-Click.zip) |

### 安装 OpenAI Codex CLI

| 系统 | 下载 |
|---|---|
| macOS | [下载：OpenAI Codex 安装器（双击执行）](https://github.com/mileson/glm-claude-auto-install/releases/latest/download/OpenAI-Codex-macOS-Double-Click.command) |
| Windows | [下载：OpenAI Codex 安装器（下载后双击执行）](https://github.com/mileson/glm-claude-auto-install/releases/latest/download/OpenAI-Codex-Windows-Download-Then-Double-Click.zip) |

---

### 第 3 步：下载后直接执行

#### macOS

1. 下载 `.command` 文件到桌面或下载目录
2. 双击运行
3. 如果系统提示安全确认，按提示允许
4. 根据窗口提示输入需要的信息
5. 等它自动安装完成

#### Windows

1. 下载 `.zip` 文件到本地
2. 先解压
3. 双击里面名字带 **双击执行** 的 `.bat`
4. 如果系统弹出管理员授权，点击允许
5. 根据窗口提示输入需要的信息
6. 等它自动安装完成

---

## 为什么 release 里现在应该只保留 4 个主文件

因为大多数用户真正需要的只有：

1. mac 版智谱 Claude Code
2. Windows 版智谱 Claude Code
3. mac 版 OpenAI Codex
4. Windows 版 OpenAI Codex

清理旧版环境属于少数情况，不应该放在主下载区让新手分心。

如果以后真的需要清理旧版 GLM 环境，可以直接到仓库里的 `scripts/` 目录获取对应脚本。

---

## 下载后会发生什么

安装器会自动帮用户完成这些事：

- 检查电脑里有没有 `node`、`npm`、`npx`
- 没有的话自动安装 **系统级 Node.js**
- 自动安装对应 CLI
- 自动写入本地配置文件
- 安装前自动备份旧配置

---

## 两类安装器分别会让用户输入什么

### GLM Coding Plan + Claude Code

通常会引导用户输入：

- 套餐区域（中国站 / Global）
- API Key

然后自动完成：

- Node.js 安装（如缺失）
- Claude Code 安装
- Coding Helper 安装
- Claude 配置写入

### OpenAI Codex CLI

通常会引导用户输入：

- Base URL
- OpenAI API Key
- 默认模型
- reasoning effort

然后自动完成：

- Node.js 安装（如缺失）
- Codex CLI 安装
- `~/.codex/config.toml` 写入
- `~/.codex/auth.json` 写入

---

## 常见问题

### 为什么 release 页面里还有 Source code (zip / tar.gz)

这是 GitHub 自动生成的源码包，不是给普通用户直接双击运行的安装器。

如果你只是想安装，请优先下载这些名字的文件：

- `Double-Click.command`
- `Download-Then-Double-Click.zip`

### Windows 为什么是 zip，不是直接一个文件

因为 Windows 安装器通常需要：

- 一个可双击启动的 `.bat`
- 一个实际执行逻辑的 `.ps1`

所以这里直接打成一个 zip，用户下载一个文件就够了。

### 我是新手，应该下载哪个

最简单的判断：

- 想装 **GLM + Claude** → 选名字里有 `GLM-Claude`
- 想装 **OpenAI Codex** → 选名字里有 `OpenAI-Codex`
- 用 mac → 选 `.command`
- 用 Windows → 选 `.zip`

---

## 给第一次使用的人一句话建议

- 不要下载 `Source code`
- 直接点上面的下载链接
- 下载到本地后按系统双击执行
- 跟着提示一步一步填就行

---

## 适合谁用

- 不会自己配 Node.js 的新手
- 不想手动敲很多命令的用户
- 需要把安装流程交给别人执行的人
- 想降低远程协助成本的人

## 功能亮点

- 新手友好的双击安装入口
- 自动检测并安装 Node.js
- 自动安装 GLM Claude / OpenAI Codex
- 自动写入本地配置
- 自动备份旧配置
- 提供旧版 GLM 环境清理脚本
- 同时支持 macOS 与 Windows

## 使用说明

- GLM 安装器基于官方 Coding Tool Helper 流程与 Node.js 官方安装包。
- Codex 安装器基于官方 npm 安装路径，并自动写入本地配置。
- Codex CLI 在 Windows 上更适合作为实验性方案，长期使用仍建议 WSL2。
- 如果你是给别人分发，可以直接把上面的下载链接发给对方。

## 安全说明

- 不要把真实 API Key 提交到仓库。
- 安装器会在写入前备份旧配置。
- `~/.codex/auth.json`、`~/.chelper/config.yaml`、Claude 配置文件都应只保留在本地。
- 如发现安全问题，请查看 [SECURITY.md](./SECURITY.md)。

## 版本说明

- [v0.1.4](./docs/releases/v0.1.4.md)

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
