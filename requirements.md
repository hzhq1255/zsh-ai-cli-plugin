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
| `codex-s2a` | sub2api |
| `codex-ds` | DeepSeek |
| `codex-openai` | OpenAI (默认) |
| `codex-wj` | 万界方舟 |

### 4. 启动 Provider
- Claude 别名通过 `cc-switch start claude <provider> -- <native args...>` 启动
- Codex 别名通过 `cc-switch config show` 获取指定 provider 的 ID、`config.toml` 和认证配置
- Codex profile 按 provider ID 写入 `${CODEX_HOME:-$HOME/.codex}/{provider-id}.config.toml`
- profile 是叠加层，不能替代共享 `CODEX_HOME/config.toml`
- Codex 使用共享 `CODEX_HOME` 启动 `codex --profile <provider-id> ...`，保证会话与 `resume` 共通
- 第三方 Codex profile 统一使用 `env_key = "CUSTOM_API_KEY"`，仅在子进程中注入认证；OpenAI Official 不修改共享 `auth.json`
- 启动指定 Provider 时不切换全局当前 Provider
- 原生参数原样透传；Codex 的 `--profile`/`-p` 由 alias 管理
- `doctor` 等不支持 `--profile` 的 Codex 管理命令直接使用原生 `codex`

### 5. 依赖检查
- 使用时检查 cc-switch 是否已安装 `curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash`
- 提供清晰的安装指引
- Codex alias 使用时检查 `jq` 是否已安装，缺失时提示 `brew install jq`

### 6. Provider 验证
- 启动前验证 Provider 是否已配置
- 未配置时提示配置方法
