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
| `codex-hyb` | 黑与白公益站 | codex |

## 依赖

- [cc-switch-cli](https://github.com/SaladDay/cc-switch-cli) - AI 提供商切换工具
- [claude-code](https://github.com/anthropics/claude-code) - Claude CLI
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

### 5. 重新加载 shell

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
```

### 查看/管理 Provider

```bash
# 查看当前 provider
ccs provider current

# 列出所有 providers
ccs provider list

# 切换 provider
ccs provider switch DeepSeek
```

## 别名

插件提供了以下别名：

```zsh
ccs  # cc-switch 的简写
```

## 配置示例

### cc-switch provider 配置

在 `~/.config/cc-switch/config.yaml` 中配置：

```yaml
providers:
  "Zhipu GLM":
    base_url: "https://open.bigmodel.cn/api/anthropic"
    api_key: "your-api-key"
    model: "glm-4.7"

  DeepSeek:
    base_url: "https://api.deepseek.com/anthropic"
    api_key: "your-api-key"
    model: "deepseek-chat"
```

## 许可

MIT License
