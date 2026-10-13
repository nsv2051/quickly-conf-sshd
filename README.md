# quickly-conf-sshd

一条命令把 GitHub 上的 SSH 公钥部署到服务器，并保持定期自动更新。

这个脚本可以帮你做到这些事情：

- 快速配置服务器的 SSH Server；
- 定期自动更新 SSH 公钥到服务器中；
- 集中管理注册到服务器的 SSH 公钥（例如使用 GitHub 管理 SSH 公钥）。

> 基于 [LamGC/quickly-conf-sshd](https://github.com/LamGC/quickly-conf-sshd) 重构。

## Quick Usage

部署密钥并设置定期更新：

```bash
curl -s https://ssh.nnn.cx | bash -s -- -c
```

如果不希望自动更新密钥，可以移除 `-c` 参数：

```bash
curl -s https://ssh.nnn.cx | bash -s
```

跳过检查 SSH Server，只需要安装秘钥的话，就需要单独使用 `-o` 参数：

```bash
curl -s https://ssh.nnn.cx | bash -s -- -o
```

添加 `-p yes` 参数可以设置允许 Root 用户使用密码登录 SSH（需使用 Root 用户执行脚本）：

```bash
curl -s https://ssh.nnn.cx | bash -s -- -p yes
```

添加 `-P yes` 参数可以关闭密码登录，改为仅允许密钥登录（需使用 Root 用户执行脚本）：

```bash
curl -s https://ssh.nnn.cx | bash -s -- -P yes
```

> 执行前请先用密钥开一个新会话验证能登录，否则会失去远程访问；脚本会自动备份、校验并 reload sshd（不会断开现有连接）。

要查看脚本的帮助信息，请使用 `-h` 参数：

```bash
curl -s https://ssh.nnn.cx | bash -s -- -h
```

> Note: 更多用法请参见脚本帮助信息~

## 参数说明

使用 `bash -s -- <参数>` 传入参数（示例见上一节）：

| 参数 | 说明 |
| --- | --- |
| `-c [<cron>]` / `--cron` | 配置 Crontab 定期自动更新公钥；`-c false` 则删除 Crontab |
| `-o` / `--only-update-keys` | 只更新公钥，不检查 / 改动 SSH Server 配置 |
| `-u` / `--update-self` | 将本地脚本更新到最新版本 |
| `-n` / `--no-install-sshd` | 不安装 SSH Server（仅 Root） |
| `-p <yes \| no>` / `--allow-root-passwd` | 是否允许 Root 用**密码**登录。注意：**只写入 `PermitRootLogin`，不会改变密码认证本身**（仅 Root） |
| `-P <yes \| no>` / `--disable-password-auth` | **关闭 / 开启密码登录**（`-P yes` 即仅允许密钥登录）：写入 `/etc/ssh/sshd_config.d/50-disable-password.conf` 并 reload sshd（仅 Root） |
| `--uninstall` | 卸载：移除 Crontab 与本地脚本文件（不改动 `authorized_keys` 受管块与 `sshd_config`） |
| `-h` / `--help` | 显示帮助信息 |

注意事项：

- 改动 `sshd_config` 前自动备份为 `.bak.conf-sshd`；改动后执行 `sshd -t` 校验，失败自动回滚；成功后 `reload` sshd，无需手动重启，也不会断开现有连接。
- 使用 `-P yes` 之前，请先用密钥开一个新会话确认可以登录，否则关闭密码登录后将失去远程访问。
- 公钥写入 `~/.ssh/authorized_keys` 的受管块（`# --- BEGIN/END MANAGED BY CONF-SSHD SCRIPT ---`），块外的自定义内容会保留；覆盖前生成 `authorized_keys.bak` 备份。
- 受管块若缺少 `END` 标记，脚本会拒绝更新（避免误删块外内容）。
- 公钥取自 `https://{Worker 地址}/ssh.keys`，默认来自你 GitHub 账号下的 SSH 公钥。请留意：**谁能改动该地址或你的 GitHub 账号，谁就能登录所有执行过本脚本的服务器**；不需要自动更新时可用 `--uninstall` 断开。
- 仓库与 Worker 中**只放公钥**，不要提交私钥。

## Paths

获取 SSH 公钥：

```
https://ssh.nnn.cx/ssh.keys
```

获取 Shell 脚本：

```
https://ssh.nnn.cx/script.sh
```

获取 Shell 脚本（使用 Curl / Wget 访问）：

```
https://ssh.nnn.cx/
```

访问落地页（浏览器访问）：

```
https://ssh.nnn.cx/
```

## 项目结构

```
.
├── wrangler.toml          # Worker 配置（入口、文本模块规则）
├── package.json           # 固定 wrangler 版本，供 Workers Builds 使用
├── src/
│   ├── worker.js          # Worker 入口：路径路由与请求处理
│   ├── config.js          # 环境变量读取（配置项全部来自环境变量）
│   └── landing.js         # 落地页文案与 HTML 渲染
├── script/
│   └── conf-sshd.sh       # 安装脚本（作为文本模块打入 Worker）
├── docs/                  # 文档配图
└── .github/workflows/     # GitHub Actions
```

## 配置

所有配置项均通过环境变量设置。在 **Cloudflare 面板 → 该 Worker → Settings → Variables and Secrets** 添加。代码里统一用 `env.<变量名>` 读取。

| 变量名 | 必填 | 作用 | 默认值 |
| --- | --- | --- | --- |
| `GITHUB_USER_NAME` | **是** | 分发谁的 GitHub 公钥（决定 `/ssh.keys` 的取源） | 无，未设置时 `/ssh.keys` 报错 |
| `CRON_EXPRESSION` | 否 | 脚本中 `-c` 的默认 cron 计划 | `0 0 * * *` |
| `BACKUP_SSH_KEYS` | 否 | 内联备用公钥（多行文本原样使用） | 空 |
| `SSH_KEY_URLS` | 否 | 额外公钥来源（换行或英文逗号分隔，例如 Keybase） | 空 |

公钥来源顺序：`https://github.com/<GITHUB_USER_NAME>.keys`，然后是 `SSH_KEY_URLS` 中的地址；**全部失败**时才回落到 `BACKUP_SSH_KEYS`。

文案 / 非敏感配置用 **Variables**；真正的密钥用 **Secrets**（写入后不可读回）。

> 本地开发可在仓库根目录新建 `.dev.vars` 文件填写同名变量（已加入 `.gitignore`，不会提交）。

## 部署 Worker

### 方式一：Workers Builds（推荐）

绑定仓库后 `push` 到 `main` 即自动构建部署，无需手动复制代码。

1. Cloudflare 面板 → **Workers & Pages** → 进入本 Worker → **Settings → Builds → Connect**；
2. 授权 GitHub 并选择本仓库，分支选 `main`；
3. **Root directory 留空**（`wrangler.toml` 位于仓库根目录）；
4. Build command 留空，Deploy command 保持默认 `npx wrangler deploy`；
5. 保存后触发一次构建。

> ⚠️ 面板中的 Worker 名称必须与 `wrangler.toml` 中的 `name`（`quickly-conf-ssh-worker`）一致，否则构建会因名称不匹配失败。

### 方式二：Wrangler CLI

在仓库根目录执行：

```bash
npx wrangler deploy
```

### 方式三：控制台手动部署

不使用 Git 集成时，可在 Cloudflare 控制台部署：新建 Worker（类型选 HTTP 处理程序），或使用 Wrangler 直接发布。

![Create a new worker](docs/Create-a-new-worker.png)

### 部署后自检

- 浏览器访问 Worker 地址，应显示落地页；
- 访问 `{Worker地址}/ssh.keys`，应返回你在 GitHub 上登记的公钥；若报 500 并提示 `GITHUB_USER_NAME is not configured`，说明**必填变量尚未设置**；
- 访问 `{Worker地址}/script.sh`，应返回安装脚本，且脚本开头的 `cron` 与 `CRON_EXPRESSION` 一致。

> 首次部署务必逐项自检。若把别人的公钥装进了自己的服务器，等于把访问权交给了别人。

### （可选）使用自定义域名

在 Worker 详情页点击「触发器」，再点击「添加自定义域」，按提示输入已托管在 Cloudflare 的域名即可。

![Add Custom Domain](docs/add-custom-domain.png)

![Input Custom Domain](docs/input-custom-domain.png)

![Added Custom Domain](docs/added-custom-domain.png)

## 安全说明

- 公钥写入 `~/.ssh/authorized_keys` 的受管块（`# --- BEGIN/END MANAGED BY CONF-SSHD SCRIPT ---`），块外的自定义内容会保留；覆盖前生成 `authorized_keys.bak` 备份。
- 受管块若缺少 `END` 标记，脚本会拒绝更新，避免误删块外内容。
- 改动 `sshd_config` 前先备份为 `.bak.conf-sshd`，改完用 `sshd -T` 核对**实际生效的值**，不符自动撤销并 reload。
- 公钥来源是 `{Worker 地址}/ssh.keys`。**谁能改动该地址或你的 GitHub 账号，谁就能登录所有执行过本脚本的服务器**；不需要自动更新时可用 `--uninstall` 断开。
- 配置项（含备用公钥）一律通过 Cloudflare 面板的 Variables / Secrets 管理，**不要写进代码或提交进仓库**。
- 仓库与 Worker 中**只放公钥**，不要提交私钥。

## 来源与致谢

本仓库基于 [LamGC/quickly-conf-sshd](https://github.com/LamGC/quickly-conf-sshd)（作者 [LamGC](https://github.com/LamGC)）重构而来，感谢原作者的工作。上游采用 Apache-2.0 协议，本仓库沿用同一协议。

## License

[Apache License 2.0](LICENSE)
