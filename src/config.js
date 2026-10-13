// ============================================================
// 默认配置：不设置任何环境变量时，Worker 使用下面的默认值照常工作。
// 可在 Cloudflare 面板 → 该 Worker → Settings → Variables and Secrets 覆盖。
// 规则：环境变量有值就用环境变量，否则用此处的默认值。
// ============================================================
export const configDefaults = {
  // 分发谁的 GitHub 公钥（决定 /ssh.keys 的取源），注意是登录 GitHub 的用户名。
  GITHUB_USER_NAME: "nsv2051",
  // 脚本中 -c 的默认 cron 计划。
  CRON_EXPRESSION: "0 0 * * *",
};

// ------------------------------------------------------------
// 备用通道（老板要求保留，不放进环境变量，改这里即可）：
// ------------------------------------------------------------
// 1) 备用公钥来源：GitHub 之外额外的公钥地址，主源拉取失败时按顺序尝试。
export const extraSshKeyUrls = [];
// 2) 内联备用公钥：所有来源都失败时直接返回这段文本（多行，原样输出）。
export const backupSshKeys = ``;
// 3) 脚本外部源：留空则使用仓库内置的 script/conf-sshd.sh；
//    填了则优先从该地址拉取，拉取失败自动回落到内置脚本。
export const installScriptUrlOverride = "";

// 读取配置：环境变量优先，否则用上面的默认值。返回完整配置对象。
export function readConfig(env) {
  env = env || {};
  const githubUserName = env.GITHUB_USER_NAME || configDefaults.GITHUB_USER_NAME;
  const cronExpression = env.CRON_EXPRESSION || configDefaults.CRON_EXPRESSION;
  return {
    githubUserName,
    cronExpression,
    // /ssh.keys 的来源：GitHub 账号公钥 + 额外备用来源
    sshKeyUrls: [`https://github.com/${githubUserName}.keys`, ...extraSshKeyUrls],
    backupSshKeys,
    installScriptUrlOverride,
  };
}
