# zsh-ai-cli-plugin

AI CLI 工具快捷封装插件，基于 [cc-switch-cli](https://github.com/SaladDay/cc-switch-cli) 管理多个 AI 提供商。

## 功能

通过便捷函数快速切换 AI 提供商并调用对应的 CLI 工具：

| 函数 | 提供商 | CLI 工具 |
|------|--------|----------|
| `glm` | 智谱 AI (bigmodel) | claude |
| `deepseek` | DeepSeek | claude |
| `kimi` | Moonshot Kimi | claude |
| `modelscope` | 魔搭平台 | claude |
| `minimaxi` | MiniMax AI | claude |
| `hybgzs` | hybgzs API | claude |
| `ccr-code` | Claude Code Router | claude |
| `gemini` | Google Gemini | gemini |
| `codex-cpa` | Codex CPA | codex |
| `codex-hyb` | Codex Hybgzs | codex |

## 依赖

- [cc-switch-cli](https://github.com/SaladDay/cc-switch-cli) - AI 提供商切换工具
- [claude-code](https://github.com/anthropics/claude-code) - Claude CLI
- [gemini-cli](https://github.com/google-gemini/gemini-cli) - Gemini CLI (可选)
- [codex-cli](https://github.com/example/codex) - Codex CLI (可选)

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
# 进入交互模式配置
cc-switch

# 或命令行添加
cc-switch provider add
```

将你的 API 配置添加到 cc-switch 的 provider 中：

| Provider | Base URL |
|----------|----------|
| bigmodel | `https://open.bigmodel.cn/api/anthropic` |
| deepseek | `https://api.deepseek.com/anthropic` |
| modelscope | `https://api-inference.modelscope.cn` |
| kimi | `https://api.kimi.com/coding/` |
| minimaxi | `https://api.minimaxi.com/anthropic` |
| hybgzs | `https://ai.hybgzs.com/claude` |
| ccr | `http://127.0.0.1:3456` |

### 5. 重新加载 shell

```bash
exec zsh
```

## 使用

### 基本用法

```bash
# 使用智谱 AI
glm "帮我写一个 Python 函数"

# 使用 DeepSeek
deepseek "解释这段代码"

# 使用 Kimi
kimi --version

# 使用 Gemini
gemini "帮我分析这个问题"

# 使用 Codex
codex-cpa "生成一个 REST API"
```

### 查看/管理 Provider

```bash
# 查看当前 provider
cc provider current

# 列出所有 providers
cc provider list

# 切换 provider
cc provider switch deepseek
```

## 别名

插件提供了以下别名：

```zsh
cc  # cc-switch 的简写
```

## 配置示例

### cc-switch provider 配置

在 `~/.config/cc-switch/config.yaml` 中配置：

```yaml
providers:
  bigmodel:
    base_url: "https://open.bigmodel.cn/api/anthropic"
    api_key: "your-api-key"
    model: "glm-4.7"

  deepseek:
    base_url: "https://api.deepseek.com/anthropic"
    api_key: "your-api-key"
    model: "deepseek-chat"
```

## 许可

MIT License
