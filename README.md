# quickly-conf-sshd

一条命令把 GitHub 上的 SSH 公钥部署到服务器，并保持定期自动更新。

这个脚本可以帮你做到这些事情：

- 快速配置服务器的 SSH Server；
- 定期自动更新 SSH 公钥到服务器中；
- 集中管理注册到服务器的 SSH 公钥（例如使用 GitHub 管理 SSH 公钥）。

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
│   ├── config.js          # 默认配置、环境变量读取、备用通道
│   └── landing.js         # 落地页文案与 HTML 渲染
├── script/
│   └── conf-sshd.sh       # 安装脚本（作为文本模块打入 Worker）
├── docs/                  # 文档配图
└── .github/workflows/     # GitHub Actions
```

## 配置

### 环境变量（可选）

在 **Cloudflare 面板 → 该 Worker → Settings → Variables and Secrets** 设置。**不设置任何变量时使用代码内置默认值，Worker 照常工作。**

| 变量名 | 作用 | 默认值 |
| --- | --- | --- |
| `GITHUB_USER_NAME` | 分发谁的 GitHub 公钥（决定 `/ssh.keys` 的取源） | `nsv2051` |
| `CRON_EXPRESSION` | 脚本中 `-c` 的默认 cron 计划 | `0 0 * * *` |

文案 / 非敏感配置用 **Variables**；真正的密钥用 **Secrets**（写入后不可读回）。代码里统一用 `env.<变量名>` 读取。

### 备用通道

以下三项以常量形式写在 `src/config.js` 中，改文件即可，不占环境变量：

| 常量 | 作用 |
| --- | --- |
| `extraSshKeyUrls` | GitHub 之外的额外公钥来源；主源拉取失败时按顺序尝试 |
| `backupSshKeys` | 所有公钥来源都失败时，直接返回的内联公钥文本 |
| `installScriptUrlOverride` | 从外部地址拉取安装脚本；留空使用仓库内置脚本，拉取失败自动回落到内置脚本 |

## 部署 Worker

### 方式一：Workers Builds（推荐）

绑定仓库后 `push` 即自动构建部署。

1. Cloudflare 面板 → **Workers & Pages** → 进入本 Worker → **Settings → Builds → Connect**；
2. 选择 GitHub 账号与仓库，分支选 `main`；
3. **Root directory 留空**（`wrangler.toml` 已在仓库根）；
4. Build command 留空；Deploy command 保持默认 `npx wrangler deploy`。

> ⚠️ 面板中的 Worker 名称必须与 `wrangler.toml` 里的 `name` 一致，否则构建报错。

### 方式二：Wrangler

在仓库根目录执行：

```bash
npx wrangler deploy
```

### 方式三：面板粘贴

在 Cloudflare Workers 中新建（或打开已有）Worker，选择 HTTP 处理程序，把 `src/worker.js`、`src/config.js`、`src/landing.js` 三份内容按模块方式部署；或直接使用上面的 Wrangler 方式，更省事。

![Create a new worker](docs/Create-a-new-worker.png)

保存后检查：

- 浏览器访问 Worker 地址，应显示落地页；
- 访问 `{Worker地址}/ssh.keys`，应显示你在 GitHub 设置的所有 SSH 公钥；为空或不是你的密钥，检查 `GITHUB_USER_NAME` 是否填对；
- 访问 `{Worker地址}/script.sh`，应返回安装脚本。

### （可选）使用自定义域名

在 Worker 详情中点击「触发器」，再点击「添加自定义域」，按提示输入已添加在 Cloudflare 中的域名即可。

![Add Custom Domain](docs/add-custom-domain.png)

![Input Custom Domain](docs/input-custom-domain.png)

![Added Custom Domain](docs/added-custom-domain.png)

## 安全说明

- 公钥写入 `~/.ssh/authorized_keys` 的受管块（`# --- BEGIN/END MANAGED BY CONF-SSHD SCRIPT ---`），块外自定义内容会保留；覆盖前生成 `authorized_keys.bak` 备份。
- 受管块若缺少 `END` 标记，脚本会拒绝更新（避免误删块外内容）。
- 改动 `sshd_config` 前先备份为 `.bak.conf-sshd`，改完用 `sshd -T` 核对**实际生效值**，不符自动撤销并 reload。
- 公钥来源是 `{Worker 地址}/ssh.keys`。**谁能改动该地址或你的 GitHub 账号，谁就能登录所有执行过本脚本的服务器**；不需要自动更新时可用 `--uninstall` 断开。
- 仓库与 Worker 中**只放公钥**，不要提交私钥。

## License

见 [LICENSE](LICENSE)。
