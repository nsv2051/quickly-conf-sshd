// ============================================================
// 配置读取
// 所有配置项均来自环境变量，在 Cloudflare 面板设置：
//   该 Worker → Settings → Variables and Secrets
// 本文件不含任何部署相关的硬编码值（唯一例外是下述通用 cron 兜底）。
// ============================================================

// 通用兜底：cron 计划（非身份信息，未设置 CRON_EXPRESSION 时使用）。
const DEFAULT_CRON = "0 0 * * *";

// 收集某变量及其编号变体（NAME、NAME_1、NAME_2 … NAME_20）的非空值，
// 便于在 Cloudflare 面板里分多个单行变量填写。
function collectEnv(env, base, max = 20) {
  const out = [];
  const add = (v) => {
    const s = (v || "").trim();
    if (s) out.push(s);
  };
  add(env[base]);
  for (let i = 1; i <= max; i += 1) add(env[`${base}_${i}`]);
  return out;
}

// 读取配置：环境变量优先，返回完整配置对象。
export function readConfig(env) {
  env = env || {};

  // 你的 GitHub 用户名，决定 /keys 首选的公钥来源。
  // 未设置时仍可使用 SSH_KEY_URLS / BACKUP_SSH_KEYS 作为来源。
  const githubUserName = (env.GITHUB_USER_NAME || "").trim();

  // 脚本中 -c 的默认 cron 计划。
  const cronExpression = env.CRON_EXPRESSION || DEFAULT_CRON;

  // 额外公钥来源：SSH_KEY_URLS、SSH_KEY_URLS_1 … 各自再按换行/逗号切分，去掉空白项。
  const extraKeyUrls = collectEnv(env, "SSH_KEY_URLS")
    .flatMap((s) => s.split(/[\n,]/))
    .map((s) => s.trim())
    .filter((s) => s.length > 0);

  // 内联备用公钥：BACKUP_SSH_KEYS、BACKUP_SSH_KEYS_1 … 合并（各变量可为单行一把公钥）。
  const backupSshKeys = collectEnv(env, "BACKUP_SSH_KEYS").join("\n");

  return {
    githubUserName,
    cronExpression,
    // 公钥来源顺序：GitHub 账号公钥，其次额外来源。
    sshKeyUrls: githubUserName
      ? [`https://github.com/${githubUserName}.keys`, ...extraKeyUrls]
      : extraKeyUrls,
    githubKeysUrl: githubUserName
      ? `https://github.com/${githubUserName}.keys`
      : null,
    extraKeyUrls,
    backupSshKeys,
  };
}
