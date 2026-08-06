# zsh-ai-cli-plugin

AI CLI 工具快捷封装插件，基于 [cc-switch-cli](https://github.com/SaladDay/cc-switch-cli) 管理多个 AI 提供商。

## 功能

通过便捷函数选择 AI 提供商并调用对应的 CLI 工具：

| 函数 | 提供商 | CLI 工具 |
|------|--------|----------|
| `glm` | 智谱 GLM (Zhipu GLM) | claude |
| `deepseek` | DeepSeek | claude |
| `modelscope` | 魔搭平台 (ModelScope) | claude |
| `minimaxi` | MiniMax AI | claude |
| `hybgzs` | 黑与白 | claude |
| `nvidia` | Nvidia | claude |
| `ccwj` | 万界方舟 | claude |
| `codex-cpa` | Codex CPA | codex |
| `codex-hyb` | 黑与白 | codex |
| `codex-hc` | hc | codex |
| `codex-s2a` | sub2api | codex |
| `codex-ds` | DeepSeek | codex |
| `codex-openai` | OpenAI Official | codex |
| `codex-wj` | 万界方舟 | codex |

## 依赖

- [cc-switch-cli](https://github.com/SaladDay/cc-switch-cli) - AI 提供商切换工具
- [claude-code](https://github.com/anthropics/claude-code) - Claude CLI
- Codex CLI
- `jq` - Codex alias 读取 `cc-switch config show` 配置

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
| 万界方舟 | (按你的 cc-switch 配置) | (按你的 cc-switch 配置) |

**Codex provider 配置** (通过 cc-switch 的 codex app 管理):

| Provider | base_url | model |
|----------|----------|-------|
| CPA | `https://cliproxyapi.hzhq1255.work` | `gpt-5.4` |
| 黑与白 | `https://ai.hybgzs.com/v1` | `gpt-5.4` |
| hc | (按你的 cc-switch 配置) | (按你的 cc-switch 配置) |
| sub2api | `https://sub2api.hzhq1255.work/v1` | (按你的 cc-switch 配置) |
| DeepSeek | `https://api.deepseek.com` | `gpt-5.6` |
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

# 使用万界方舟 Claude
ccwj "介绍一下你自己"

# 使用 Codex
codex-cpa "生成一个 REST API"

# 使用 OpenAI 官方 Codex
codex-openai "生成一个 REST API"

# 使用 Sub2API Codex
codex-s2a "生成一个 REST API"

# 使用 DeepSeek Codex
codex-ds "分析这个项目的目录结构"

# 在共享会话目录中恢复指定会话；继续使用对应 provider alias
codex-s2a resume 019fd0c7-9ced-7732-b365-c429ce57e706
codex-openai resume 019fd0c7-9ced-7732-b365-c429ce57e706

# 使用万界方舟 Codex
codex-wj "重构这个 shell 插件"

# 使用 hc Codex
codex-hc "检查这个项目"
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

Claude 和 Codex 使用不同的启动路径。Claude 继续由 `cc-switch start` 启动；Codex 不使用 `cc-switch start` 的临时 `CODEX_HOME`，避免进程退出后会话目录被清理。

### 启动方式

| 特性 | 本插件实现 |
|------|----------|
| Claude 实现原理 | `cc-switch start claude <provider> -- <native args...>` |
| Codex 配置来源 | `cc-switch config show` |
| Codex profile | 写入 `${CODEX_HOME:-$HOME/.codex}/{provider-id}.config.toml`，并使用 `codex --profile {provider-id}` |
| Profile 关系 | 这是叠加层，不是独立完整配置；应保留共享 `CODEX_HOME/config.toml` |
| Codex 会话 | 所有 Codex alias 使用同一个 `CODEX_HOME`，因此 `resume`、会话列表和历史保持共通 |
| 第三方认证 | 仅在 Codex 子进程中注入 `CUSTOM_API_KEY`，profile 将 provider 切换为 `env_key = "CUSTOM_API_KEY"` 认证 |
| 官方认证 | 不注入第三方 API key，不修改共享 `auth.json`，继续使用官方登录凭据 |
| 隔离性 | provider 配置通过 profile 隔离，认证通过子进程环境隔离，不切换全局当前 Provider |
| CLI 契约 | Codex 原生参数原样透传；`--profile`/`-p` 由 alias 管理，不能重复传入 |

### 核心函数

- `_ai_cli_start`: 检查 `cc-switch` 并调用 `cc-switch start`
- `_ai_cli_run_codex`: 读取 provider ID、落盘 profile、隔离认证环境并调用原生 Codex
- Codex 认证：优先读取 provider profile 声明的 `env_key` 对应 auth；没有声明时兼容 `*_API_KEY`
- Claude 别名：将 Provider 名称映射为 `cc-switch start` 的选择器，并透传原生参数
- Codex 别名：将 Provider 名称映射为 `cc-switch` 配置中的精确 provider 名称，并透传原生参数

Codex 的 `doctor` 不支持 `--profile`，需要直接运行 `codex doctor`；provider alias 适用于会话、`exec`、`resume`、`mcp` 等支持 profile 的运行命令。

```bash
# Claude
cc-switch start claude DeepSeek -- "解释这段代码"

# Codex
cc-switch config show
codex-hyb --model gpt-5.4 "生成一个 REST API"
```

## 别名

插件提供了以下别名：

```zsh
ccs  # cc-switch 的简写
```

## 许可

MIT License
