# ai-cli 插件需求

## 功能需求

### 1. 快捷切换 AI Provider
通过简短命令快速切换到指定的 AI Provider，无需手动配置环境变量。

### 2. 支持 Claude CLI
| 命令 | Provider |
|------|----------|
| `deepseek` | DeepSeek |
| `glm` | 智谱 GLM |
| `modelscope` | ModelScope |
| `minimaxi` | MiniMax |
| `hybgzs` | 黑与白 |
| `nvidia` | Nvidia |

### 3. 支持 Codex CLI
| 命令 | Provider |
|------|----------|
| `codex-cpa` | CPA |
| `codex-hyb` | 黑与白 |
| `codex-hc` | hc |
| `codex-openai` | OpenAI (默认) |
| `codex-wj` | 万界方舟 |

### 4. 通过 cc-switch 启动 Provider
- 别名通过 `cc-switch start claude <provider> -- <native args...>` 或 `cc-switch start codex <provider> -- <native args...>` 启动对应 CLI
- 由 cc-switch 读取 Provider 配置并完成环境变量、认证和 CLI 配置注入
- 启动指定 Provider 时不切换全局当前 Provider
- `--` 之后的参数原样透传给对应的 Claude 或 Codex CLI

### 5. 依赖检查
- 使用时检查 cc-switch 是否已安装 `curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash`
- 提供清晰的安装指引
- 插件不再需要自行安装 jq、yq 等配置解析工具

### 6. Provider 验证
- 启动前验证 Provider 是否已配置
- 未配置时提示配置方法
