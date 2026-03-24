# zsh-ai-cli-plugin

AI CLI 工具快捷封装插件，基于 [cc-switch-cli](https://github.com/SaladDay/cc-switch-cli) 管理多个 AI 提供商。

## 功能

通过便捷函数快速切换 AI 提供商并调用对应的 CLI 工具：

| 函数 | 提供商 | CLI 工具 |
|------|--------|----------|
| `glm` | 智谱 GLM (Zhipu GLM) | claude |
| `deepseek` | DeepSeek | claude |
| `modelscope` | 魔搭平台 (ModelScope) | claude |
| `minimaxi` | MiniMax AI | claude |
| `hybgzs` | 黑与白 | claude |
| `nvidia` | Nvidia | claude |
| `codex-cpa` | Codex CPA | codex |
| `codex-hyb` | 黑与白 | codex |
| `codex-openai` | OpenAI Official | codex |
| `codex-wj` | 万界方舟 | codex |

## 依赖

- [cc-switch-cli](https://github.com/SaladDay/cc-switch-cli) - AI 提供商切换工具
- [claude-code](https://github.com/anthropics/claude-code) - Claude CLI
- Codex CLI
- [jq](https://stedolan.github.io/jq/) - JSON 处理工具（解析 cc-switch 配置）
- [yj](https://github.com/sclevine/yj) - TOML/JSON 转换工具（解析 Codex provider 配置）

安装 jq 和 yj：
```bash
# macOS
brew install jq yj

# Linux
sudo apt-get install jq yj  # Debian/Ubuntu
sudo yum install jq yj      # CentOS/RHEL
```

## 安装

### 1. 安装 cc-switch-cli

```bash
curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash
```

### 2. 克隆插件到 oh-my-zsh custom plugins 目录

```bash
git clone https://github.com/hzhq1255/zsh-ai-cli-plugin.git ~/.oh-my-zsh/custom/plugins/ai-cli
```

### 3. 在 ~/.zshrc 中启用插件

```zsh
plugins=(... ai-cli)
```

### 4. 配置 cc-switch providers

```bash
# 进入交互式配置界面（推荐）
ccs
# 或
cc-switch

# 在界面中:
# 1. 选择 "provider" 菜单
# 2. 选择 "add" 添加新的 provider
# 3. 填写 provider 信息（名称、base_url、api_key、model）

# 也可以直接命令行添加
ccs provider add
```

**常用 provider 配置示例** (在交互式界面中填写):

| Provider | base_url | model |
|----------|----------|-------|
| Zhipu GLM | `https://open.bigmodel.cn/api/anthropic` | `glm-4.7` |
| DeepSeek | `https://api.deepseek.com/anthropic` | `deepseek-chat` |
| ModelScope | `https://api.modelscope.cn/v1` | `qwen-max` |
| MiniMax | `https://api.minimax.chat/v1` | `abab6.5s-chat` |
| 黑与白 | `https://heiyu.com/v1` | `claude-3-5-sonnet` |
| Nvidia | `https://integrate.api.nvidia.com/v1` | `meta/llama-3.1-405b-instruct` |

**Codex provider 配置** (通过 cc-switch 的 codex app 管理):

| Provider | base_url | model |
|----------|----------|-------|
| CPA | `https://cliproxyapi.hzhq1255.work` | `gpt-5.4` |
| 黑与白 | `https://ai.hybgzs.com/v1` | `gpt-5.4` |
| OpenAI Official | (官方默认) | (官方默认) |
| 万界方舟 | (按你的 cc-switch 配置) | (按你的 cc-switch 配置) |

### 5. 验证配置

```bash
# 列出 Claude providers
ccs -a claude provider list

# 列出 Codex providers
ccs -a codex provider list

# 验证配置是否有效
ccs config validate
```

### 6. 重新加载 shell

```bash
exec zsh
```

## 使用

### 基本用法

```bash
# 使用智谱 GLM
glm "帮我写一个 Python 函数"

# 使用 DeepSeek
deepseek "解释这段代码"

# 使用 Nvidia
nvidia --version

# 使用 Codex
codex-cpa "生成一个 REST API"

# 使用 OpenAI 官方 Codex
codex-openai "生成一个 REST API"

# 使用万界方舟 Codex
codex-wj "重构这个 shell 插件"
```

### 查看/管理 Provider

```bash
# 列出 Claude providers
ccs -a claude provider list

# 列出 Codex providers
ccs -a codex provider list

# 打开交互式管理界面
ccs
```

## 实现原理

本插件采用**显式 CLI 参数 + 环境变量注入**方式，而非传统的 provider 切换方式：

### 传统方式 vs 本插件

| 特性 | 传统 switch 方式 | 本插件实现 |
|------|-----------------|-----------------|
| 实现原理 | 调用 `cc-switch provider switch` | 直接从配置读取环境变量 |
| 隔离性 | 全局状态，影响所有 session | 每次调用独立，无副作用 |
| 配置来源 | 当前激活 provider | `cc-switch config show` 中对应 provider |
| 配置结构 | 仅支持 switch | Claude 用 `.env`，Codex 用 `.auth + .config(TOML)` |
| CLI 契约 | 依赖全局当前状态 | Claude 用 `--settings`，Codex 用 `-c` 覆盖 provider 相关配置 |

### 核心函数

- `_ai_cli_get_config_json`: 读取并解析 `cc-switch config show`
- `_ai_cli_run_claude`: 基于当前 `~/.claude/settings.json` 生成临时 settings 文件，清空 `.env` 后通过 `--settings` 启动 Claude
- `_ai_cli_run_codex`: 保留 `~/.codex/auth.json`，将 provider 的 TOML 配置展开为多组 `-c key=value` 参数，并按需覆盖 `model_provider` 对应的 `env_key`

```bash
# Claude: 使用显式 settings 文件和 provider 环境变量
ANTHROPIC_AUTH_TOKEN=xxx \
ANTHROPIC_BASE_URL=xxx \
claude --setting-sources project,local --settings /tmp/ai-cli-settings.json "$@"

# Codex: 保留 ~/.codex/auth.json，只覆盖 provider 配置
HYB_API_KEY=xxx \
codex \
  -c 'model_provider="custom"' \
  -c 'model_providers.custom.base_url="https://ai.hybgzs.com/v1"' \
  -c 'model_providers.custom.env_key="HYB_API_KEY"' \
  "$@"
```

## 别名

插件提供了以下别名：

```zsh
ccs  # cc-switch 的简写
```

## 许可

MIT License
