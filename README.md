# DSH 一键恢复（one-click restore）

在一台**全新 Windows 电脑**上，双击一次即可：安装 DeepSeek Harness → 拉取私有备份仓库 → 还原 `%USERPROFILE%\.dsh` → 注册每日备份任务。

> 仓库本体（备份数据）在 `AiCoderChenweishi/dsh-backup`（私有）。本仓库只放恢复工具，不含任何个人数据、密钥或会话。

## 用法

1. 新机器装好 **Git for Windows**（唯一前置依赖）。
2. 从本仓库下载 `恢复DSH.cmd`（或 `restore-dsh.cmd`），放到任意目录。
3. 双击。脚本会自动下载 `oneclick.ps1` 并执行。
4. 按提示输入一次 GitHub Token（`repo` 权限即可；本机若已登录 `gh` 会自动复用）。
5. 等待克隆与还原（首次约 1 GB，视网络 5–15 分钟）。
6. 完成后启动 DSH，**登录一次**；再双击 `%USERPROFILE%\.dsh\backup\dsh.cmd` 补装依赖（pnpm）。
7. 设置 → MCP：导入 `backup\mcp-connector.export.json`，重填显示为 `<REDACTED>` 的密钥。

## 它做了什么

| 步骤 | 说明 |
| --- | --- |
| 安装 DSH | 未安装时，从官方 nightly feed 取当前版本（实测 `0.2.2-rc.1`），校验 sha512，NSIS 静默安装 |
| 认证 | 优先复用 `gh auth token`；否则提示输入 PAT；再否则走本机 SSH key |
| 克隆 | `--single-branch main` + `core.longpaths`，避开会话路径超长 |
| 还原 | 调用备份仓库自带的 `backup\dsh-restore.ps1 -SourceRoot ...`，白名单目录镜像合并，`.env` 从 `env.dsh` 恢复，修复 `link:` 依赖 |
| 计划任务 | 每天 22:00 + 登录补跑（当日已备份则跳过） |

## 不还原的东西（设计边界）

- 账号登录态与凭据（`.credentials.yaml` 从不入库）
- MCP 密钥 / OAuth 授权（导出文件中是 `<REDACTED>`，需重填；Cloudflare 需重新授权）
- 语音模型、`dsh-runtimes` 运行时二进制（新机首次启动自动生成）

## 网络受限时

- `github.com:443` 被阻断时，脚本克隆会自动重试 `ssh.github.com:443`（需要把本机 SSH 公钥加到 GitHub）。
- `raw.githubusercontent.com` 被阻断时，`.cmd` 会自动改走 `gh-proxy.com` 镜像下载 `oneclick.ps1`。
- 两条都不可用时：在能上网的机器上下载本仓库 ZIP，解压后直接双击 `恢复DSH.cmd`。
## 恢复到某一天

备份仓库每天打一个 `backup/YYYY-MM-DD` tag。恢复旧状态：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.dsh\backup\dsh-restore.ps1" -Date 2026-11-06 -Force
```

执行前**必须关闭 DSH**。当天的 `sessions/`、`storages/`、`stratagate/`、`attachments/` 会被改名为 `*.pre-restore-<时间>` 保留，不会直接删除。

## 许可

个人自用工具，无担保。
