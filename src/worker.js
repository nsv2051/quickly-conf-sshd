import { readConfig } from "./config.js";
import { landing, renderLandingPage } from "./landing.js";
import installScript from "../script/conf-sshd.sh";

// 下面是脚本的占位符.
const SCRIPT_PH_SSH_KEY_URL = "{{ SSH_KEY_URL }}"
const SCRIPT_PH_SCRIPT_URL = "{{ SCRIPT_URL }}"
const SCRIPT_PH_DEFAULT_CRON = "{{ DEFAULT_CRON }}"

// 单个公钥来源的拉取超时（毫秒）。避免上游挂起时一直等待、无法回落备用来源。
const KEY_FETCH_TIMEOUT_MS = 10 * 1000;

// 拉取一个公钥来源。
// 返回公钥文本；以下任一情况都视为失败并返回 null，由调用方继续尝试下一个来源：
//   1. 网络异常或超时（fetch 抛错）
//   2. HTTP 状态非 2xx
//   3. 响应内容为空（trim 后长度为 0）—— GitHub 账号无公钥时返回 200 + 空 body
// 内容是否为合法公钥由服务端脚本负责校验，此处只判有无。
async function fetchKeys(url) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(KEY_FETCH_TIMEOUT_MS) });
    if (!response.ok) {
      return null;
    }
    const keys = await response.text();
    return keys.trim().length > 0 ? keys : null;
  } catch (err) {
    return null;
  }
}

async function sendScriptContent(baseUrl, config) {
  let scriptContent = installScript
    .replace(SCRIPT_PH_SSH_KEY_URL, `${baseUrl}/ssh.keys`)
    .replace(SCRIPT_PH_SCRIPT_URL, `${baseUrl}/script.sh`)
    .replace(SCRIPT_PH_DEFAULT_CRON, config.cronExpression);

  return new Response(scriptContent, {
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store"
    }
  });
}

export default {
  async fetch(request, env) {
    const config = readConfig(env);
    const { pathname, host } = new URL(request.url);
    const baseUrl = `https://${host}`;
    if (pathname === "/ssh.keys") {
      // 至少要有一个可用来源（联网来源或内联备用），否则明确报错，
      // 避免 fork 后未配置就静默拿不到钥匙（或拿到不属于自己的钥匙）。
      if (config.sshKeyUrls.length === 0 && config.backupSshKeys.trim().length === 0) {
        return new Response(
          "No SSH key source configured. 请在本 Worker 的 Settings → Variables and Secrets 中设置 GITHUB_USER_NAME（或 SSH_KEY_URLS / BACKUP_SSH_KEYS）后重试。",
          {
            status: 500,
            statusText: "No SSH key source configured",
            headers: {
              "content-type": "text/plain; charset=utf-8",
              "cache-control": "no-store"
            }
          }
        );
      }
      for (let url of config.sshKeyUrls) {
        let keys = await fetchKeys(url);
        if (keys !== null) {
          return new Response(keys, {
            headers: {
              "content-type": "text/plain; charset=utf-8",
              "cache-control": "no-store"
            }
          });
        }
      }
      if (config.backupSshKeys.trim().length > 0) {
        return new Response(config.backupSshKeys, {
          headers: {
            "content-type": "text/plain; charset=utf-8",
            "cache-control": "no-store"
          }
        });
      } else {
        return new Response("Failed to get keys.", {
          status: 500,
          statusText: "Failed to get keys",
          headers: {
            "content-type": "text/plain; charset=utf-8",
            "cache-control": "no-store"
          }
        });
      }
    } else if (pathname === "/ssh.keys/github") {
      if (config.githubKeysUrl == null) {
        return new Response("GitHub key source not configured or unavailable.", {
          status: 404,
          statusText: "Not Found",
          headers: {
            "content-type": "text/plain; charset=utf-8",
            "cache-control": "no-store"
          }
        });
      }
      let keys = await fetchKeys(config.githubKeysUrl);
      if (keys === null) {
        return new Response("GitHub key source not configured or unavailable.", {
          status: 404,
          statusText: "Not Found",
          headers: {
            "content-type": "text/plain; charset=utf-8",
            "cache-control": "no-store"
          }
        });
      }
      return new Response(keys, {
        headers: {
          "content-type": "text/plain; charset=utf-8",
          "cache-control": "no-store"
        }
      });
    } else if (pathname === "/ssh.keys/extra") {
      if (config.extraKeyUrls.length === 0) {
        return new Response("No extra key URLs configured.", {
          status: 404,
          statusText: "Not Found",
          headers: {
            "content-type": "text/plain; charset=utf-8",
            "cache-control": "no-store"
          }
        });
      }
      for (let url of config.extraKeyUrls) {
        let keys = await fetchKeys(url);
        if (keys !== null) {
          return new Response(keys, {
            headers: {
              "content-type": "text/plain; charset=utf-8",
              "cache-control": "no-store"
            }
          });
        }
      }
      return new Response("Failed to fetch keys from extra URLs.", {
        status: 502,
        statusText: "Bad Gateway",
        headers: {
          "content-type": "text/plain; charset=utf-8",
          "cache-control": "no-store"
        }
      });
    } else if (pathname === "/ssh.keys/backup") {
      if (config.backupSshKeys.trim().length === 0) {
        return new Response("No backup keys configured.", {
          status: 404,
          statusText: "Not Found",
          headers: {
            "content-type": "text/plain; charset=utf-8",
            "cache-control": "no-store"
          }
        });
      }
      return new Response(config.backupSshKeys, {
        headers: {
          "content-type": "text/plain; charset=utf-8",
          "cache-control": "no-store"
        }
      });
    } else if (pathname === "/") {
      const userAgent = request.headers.get("User-Agent");
      if (userAgent != null && userAgent.match(/curl|libcurl|wget/i) !== null) {
        return await sendScriptContent(baseUrl, config);
      } else {
        return new Response(renderLandingPage(baseUrl, landing), {
          headers: {
            "content-type": "text/html; charset=utf-8",
            "cache-control": "no-store"
          }
        });
      }
    } else if (pathname === "/script.sh") {
      return await sendScriptContent(baseUrl, config);
    } else {
      return new Response("Not found.", {
        status: 404,
        statusText: "Not Found"
      })
    }
  }
}
