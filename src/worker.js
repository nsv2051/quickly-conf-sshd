import { readConfig } from "./config.js";
import { landing, renderLandingPage } from "./landing.js";
import installScript from "../script/conf-sshd.sh";

// 下面是脚本的占位符.
const SCRIPT_PH_SSH_KEY_URL = "{{ SSH_KEY_URL }}"
const SCRIPT_PH_SCRIPT_URL = "{{ SCRIPT_URL }}"
const SCRIPT_PH_DEFAULT_CRON = "{{ DEFAULT_CRON }}"


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
      if (!config.githubUserName) {
        return new Response(
          "GITHUB_USER_NAME is not configured. 请在本 Worker 的 Settings → Variables and Secrets 中设置该变量后重试。",
          {
            status: 500,
            statusText: "GITHUB_USER_NAME is not configured",
            headers: {
              "content-type": "text/plain; charset=utf-8",
              "cache-control": "no-store"
            }
          }
        );
      }
      for (let url of config.sshKeyUrls) {
        let response = await fetch(new Request(url));
        if (response.ok) {
          let keys = await response.text()
          return new Response(keys, {
            headers: {
              "content-type": "text/plain; charset=utf-8",
              "cache-control": "no-store"
            }
          });
        }
      }
      if (config.backupSshKeys.length > 0) {
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
