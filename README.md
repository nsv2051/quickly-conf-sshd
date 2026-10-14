# SSH 公钥一键部署（Cloudflare Worker）

用一条命令把 SSH 公钥部署到服务器，并保持定期自动更新。公钥托管在一个轻量的 Cloudflare Worker 上，你改一处，所有执行过本脚本的服务器都能同步。

- **一条命令**：部署公钥并注册定期自动更新；
- **集中管理**：公钥来源集中在 Worker 侧，改一处即可同步全部服务器；
- **零依赖**：服务器端只需要 `root` 与 `curl` / `wget` 之一；
- **只写受管块，可回滚**：`authorized_keys` 只改动受管区块；改 `sshd_config` 前先备份、改后校验，不符自动回滚。

> 本项目基于 [LamGC/quickly-conf-sshd](https://github.com/LamGC/quickly-conf-sshd) 重构，沿用上游的 Apache-2.0 许可。

## 快速开始

把下文的 `YOUR_WORKER_URL` 替换为本 Worker 的访问地址（例如 `https://your-worker.example.workers.dev`，或你绑定的自定义域名）。

部署公钥并注册定期自动更新：

```bash
curl -s https://YOUR_WORKER_URL | bash -s -- -c
```

只部署公钥、不注册自动更新（去掉 `-c`）：

```bash
curl -s https://YOUR_WORKER_URL | bash -s
```

跳过 SSH Server 检查，只更新公钥：

```bash
curl -s https://YOUR_WORKER_URL | bash -s -- -o
```

关闭密码登录，改为仅密钥登录（需 `root`）：

```bash
curl -s https://YOUR_WORKER_URL | bash -s -- -P yes
```

查看帮助：

```bash
curl -s https://YOUR_WORKER_URL | bash -s -- -h
```

> 执行 `-P yes` 前，请先用密钥新开一个会话确认可以登录，否则关闭密码登录后将失去远程访问；脚本会自动备份、校验并 reload sshd（不会断开现有连接）。

## 参数说明

以 `bash -s -- <参数>` 传入：

| 参数 | 说明 |
| --- | --- |
| `-c [<cron>]` / `--cron` | 配置 crontab 定期自动更新公钥；`-c false` 则删除 crontab |
| `-o` / `--only-update-keys` | 只更新公钥，不改动 SSH Server 配置 |
| `-u` / `--update-self` | 将本地脚本更新到最新版本 |
| `-n` / `--no-install-sshd` | 不安装 SSH Server（仅 root） |
| `-p <yes \| no>` / `--allow-root-passwd` | 是否允许 root 用**密码**登录（只写入 `PermitRootLogin`，不改变密码认证本身；仅 root） |
| `-P <yes \| no>` / `--disable-password-auth` | **关闭 / 开启**密码登录（`-P yes` 即仅允许密钥登录；仅 root） |
| `--uninstall` | 卸载：移除 crontab 与本地脚本（不改动 `authorized_keys` 受管块与 `sshd_config`） |
| `-h` / `--help` | 显示帮助 |

## 接口

| 地址 | 说明 |
| --- | --- |
| `/keys` | 全部公钥（按来源顺序合并，取第一个可用来源） |
| `/keys/github` | 指定 GitHub 账号的公钥 |
| `/keys/extra` | 额外来源（`SSH_KEY_URLS`） |
| `/keys/backup` | 内联备用公钥（`BACKUP_SSH_KEYS`） |
| `/sh` | 安装脚本 |
| `/` | 浏览器访问显示落地页；`curl` / `wget` 访问返回安装脚本 |

> 旧地址 `/ssh.keys`、`/ssh.keys/github`、`/ssh.keys/extra`、`/ssh.keys/backup`、`/script.sh` 仍可用（作为短路径的别名），以兼容已部署服务器上的旧引用。

## 配置

所有配置项均通过环境变量设置，在 **Cloudflare 面板 → 该 Worker → Settings → Variables and Secrets** 添加，代码里统一用 `env.<变量名>` 读取。

| 变量名 | 必填 | 作用 | 默认值 |
| --- | --- | --- | --- |
| `GITHUB_USER_NAME` | 是* | 分发哪个 GitHub 账号的公钥（决定 `/keys` 首选来源） | 无 |
| `CRON_EXPRESSION` | 否 | 脚本中 `-c` 的默认 cron 计划 | `0 0 * * *` |
| `BACKUP_SSH_KEYS` | 否 | 内联备用公钥（各变量可为单行一把公钥） | 空 |
| `SSH_KEY_URLS` | 否 | 额外公钥来源（换行或英文逗号分隔，例如 Keybase） | 空 |

> 变量名支持**编号后缀**：`SSH_KEY_URLS`、`SSH_KEY_URLS_1`、`SSH_KEY_URLS_2` … 会被依次读取并合并；`BACKUP_SSH_KEYS` 同理。这样可以在 Cloudflare 面板里一项一行地填写（面板的值输入框是单行的）。

> \* 仅在 `SSH_KEY_URLS` 与 `BACKUP_SSH_KEYS` **都**未配置时才是硬性必填。三者至少要配一个，否则 `/keys` 返回 500。

公钥来源顺序：`https://github.com/<GITHUB_USER_NAME>.keys`，然后是 `SSH_KEY_URLS` 中的地址；**全部失败**时才回落到 `BACKUP_SSH_KEYS`。单个来源「失败」的判定包含三种情况：**网络异常或超时（10 秒）**、**HTTP 状态非 2xx**、**响应内容为空** —— 任一情况都会继续尝试下一个来源。

文案 / 非敏感配置用 **Variables**；真正的密钥用 **Secrets**（写入后不可读回）。

> 本地开发可在仓库根目录新建 `.dev.vars` 文件填写同名变量（已加入 `.gitignore`，不会提交）。

## 部署

### 方式一：Workers Builds（推荐）

绑定仓库后 `push` 到 `main` 即自动构建部署，无需手动复制代码。

1. Cloudflare 面板 → **Workers & Pages** → 进入本 Worker → **Settings → Builds → Connect**；
2. 授权 GitHub 并选择本仓库，分支选 `main`；
3. **Root directory 留空**（`wrangler.toml` 位于仓库根目录）；
4. Build command 留空，Deploy command 保持默认 `npx wrangler deploy`；
5. 保存后触发一次构建。

> ⚠️ 面板中的 Worker 名称必须与 `wrangler.toml` 中的 `name` 一致，否则构建会因名称不匹配失败。

### 方式二：Wrangler CLI

在仓库根目录执行：

```bash
npx wrangler deploy
```

### 方式三：控制台手动部署

不使用 Git 集成时，可在 Cloudflare 控制台新建 Worker（类型选 HTTP 处理程序），或将代码粘贴/发布进去。

## 部署后自检

- 浏览器访问 Worker 地址，应显示落地页；
- 访问 `{Worker地址}/keys`，应返回你的公钥；若报 500 并提示 `No SSH key source configured`，说明**尚未配置任何公钥来源**（`GITHUB_USER_NAME` / `SSH_KEY_URLS` / `BACKUP_SSH_KEYS` 至少设一个）；
- 访问 `{Worker地址}/sh`，应返回安装脚本，且脚本开头的 `cron` 与 `CRON_EXPRESSION` 一致。

> 首次部署务必逐项自检。若把别人的公钥装进了自己的服务器，等于把访问权交给了别人。

### （可选）使用自定义域名

在 Worker 详情页点击「触发器」→「添加自定义域」，按提示输入已托管在 Cloudflare 的域名即可。

## 安全说明

- 公钥写入 `~/.ssh/authorized_keys` 的受管块（`# --- BEGIN/END MANAGED BY CONF-SSHD SCRIPT ---`），块外的自定义内容会保留；覆盖前生成 `authorized_keys.bak` 备份。
- 受管块若缺少 `END` 标记，脚本会拒绝更新，避免误删块外内容。
- 改动 `sshd_config` 前先备份为 `.bak.conf-sshd`，改完用 `sshd -T` 核对**实际生效的值**，不符自动撤销并 reload。
- 公钥来源是 `{Worker 地址}/keys`。**谁能改动该地址或你的 GitHub 账号，谁就能登录所有执行过本脚本的服务器**；不需要自动更新时可用 `--uninstall` 断开。
- 配置项（含备用公钥）一律通过 Cloudflare 面板的 Variables / Secrets 管理，**不要写进代码或提交进仓库**。
- 仓库与 Worker 中**只放公钥**，不要提交私钥。

## 项目结构

```
.
├── wrangler.toml          # Worker 配置（入口、文本模块规则、keep_vars）
├── package.json           # 固定 wrangler 版本，供 Workers Builds 使用
├── src/
│   ├── worker.js          # Worker 入口：路径路由与请求处理
│   ├── config.js          # 环境变量读取（含编号后缀变量合并）
│   └── landing.js         # 落地页文案与 HTML 渲染（含内联 SVG logo）
├── script/
│   └── conf-sshd.sh       # 安装脚本（作为文本模块打入 Worker）
└── .github/workflows/     # GitHub Actions
```

## 许可

[Apache License 2.0](LICENSE)
