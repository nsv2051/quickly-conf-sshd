// ============================================================
// 配置读取
// 所有配置项均来自环境变量，在 Cloudflare 面板设置：
//   该 Worker → Settings → Variables and Secrets
// 本文件不含任何部署相关的硬编码值（唯一例外是下述通用 cron 兜底）。
// ============================================================

// 通用兜底：cron 计划（非身份信息，未设置 CRON_EXPRESSION 时使用）。
const DEFAULT_CRON = "0 0 * * *";

// 读取配置：环境变量优先，返回完整配置对象。
export function readConfig(env) {
  env = env || {};

  // 必填：你的 GitHub 用户名，决定 /ssh.keys 分发谁的公钥。
  const githubUserName = (env.GITHUB_USER_NAME || "").trim();

  // 脚本中 -c 的默认 cron 计划。
  const cronExpression = env.CRON_EXPRESSION || DEFAULT_CRON;

  // 额外公钥来源：按换行或英文逗号切分，去掉空白项。
  const extraKeyUrls = (env.SSH_KEY_URLS || "")
    .split(/[\n,]/)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);

  // 内联备用公钥：所有来源都失败时直接返回（多行原样）。
  const backupSshKeys = env.BACKUP_SSH_KEYS || "";

  return {
    githubUserName,
    cronExpression,
    // 公钥来源顺序：GitHub 账号公钥，其次额外来源。
    sshKeyUrls: githubUserName
      ? [`https://github.com/${githubUserName}.keys`, ...extraKeyUrls]
      : extraKeyUrls,
    backupSshKeys,
  };
}
