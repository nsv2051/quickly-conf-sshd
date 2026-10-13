// 改成你自己的 Github 用户名，注意是登录 Github 的那个用户名.
const githubUserName = "nsv2051";
// 改成你 Fork 后的仓库名，记得要开启 Github Pages 功能.
const githubInstSshProjectName = "quickly-conf-sshd";
// 如果可以，建议在此设置备用的 SSH 公钥, 以防 Github 无法使用.
const backupSshKeys = ``;
// Worker 的访问地址, 如果不填的话默认为请求的地址, 填了就会用这里的地址(要去 Worker 的触发器那绑定, 否则无效).
const defaultBaseUrl = "";
// Cron 表达式, 默认 1 天执行一次更新.
const cronExpression = "0 0 * * *";

// ============================================================
// 落地页配置区：浏览器访问 Worker 根路径时的所有文案 / 命令都在这里改。
// curl / wget 访问根路径依旧返回安装脚本，不受此处影响。
// 文案中的 {{BASE_URL}} 会自动替换成当前 Worker 的访问地址。
// ============================================================
const landing = {
  // 页面语言与元信息
  lang: "zh-Hans",
  title: "ssh.nnn.cx · SSH 公钥一键部署",
  description: "一条命令把 GitHub 上的 SSH 公钥部署到服务器，并保持每小时自动更新。",

  // 页头
  brand: "ssh.nnn.cx",
  brandStatus: "服务正常",
  brandSub: "SSH 公钥一键部署",
  repoLabel: "GitHub",
  repoUrl: `https://github.com/${githubUserName}/${githubInstSshProjectName}`,

  // 主标题与副标题
  headline: "一条命令，把你的 SSH 公钥部署到服务器",
  lede: `从你的 GitHub 账号同步公钥写入 \`authorized_keys\`，注册每小时自动更新，并在加固 sshd 前自动备份、校验、可回滚。零依赖，纯 shell。`,

  // 命令选择器：label 标签名，tag 角标（留空则显示，可写「推荐」），cmd 一键复制内容，hint 下方说明
  commandTabsLabel: "命令场景",
  commands: [
    {
      label: "部署 + 自动更新",
      tag: "推荐",
      cmd: "curl -s {{BASE_URL}} | bash -s -- -c",
      hint: "部署公钥并注册每小时自动更新。适合新服务器首次配置。"
    },
    {
      label: "仅更新密钥",
      tag: "",
      cmd: "curl -s {{BASE_URL}} | bash -s -- -o",
      hint: "只同步公钥，不检查也不改动 SSH Server 配置。"
    },
    {
      label: "仅密钥登录",
      tag: "",
      cmd: "curl -s {{BASE_URL}} | bash -s -- -P yes",
      hint: "关闭密码登录，仅允许密钥登录。执行前请先用密钥新开会话验证可登录。"
    },
    {
      label: "查看帮助",
      tag: "",
      cmd: "curl -s {{BASE_URL}} | bash -s -- -h",
      hint: "打印全部可用参数及说明。"
    }
  ],
  commandedLabel: "待执行命令",
  copyLabel: "复制命令",
  copyDoneLabel: "已复制 ✓",
  copyFailLabel: "复制失败",
  copyOkAnnounce: "命令已复制到剪贴板",
  copyFailAnnounce: "复制失败，请手动选择命令",

  // 功能卡片（可增删项）
  features: [
    {
      title: "每小时自动更新",
      body: "写入一条 crontab，从已登记的公钥源拉取最新内容。改动 GitHub 上的公钥即可同步到所有跑过脚本的服务器。"
    },
    {
      title: "只动受管块",
      body: "公钥只写入 \`authorized_keys\` 中标记为 \`MANAGED BY CONF-SSHD SCRIPT\` 的区块，块外内容原样保留，覆盖前先备份。"
    },
    {
      title: "改配置可回滚",
      body: "修改 \`sshd_config\` 前备份为 \`.bak.conf-sshd\`；修改后用 \`sshd -T\` 核对实际生效值，不符即撤销并 reload，不断开现有连接。"
    },
    {
      title: "零依赖",
      body: "只需要 root（或 sudo）与 \`curl\` / \`wget\`，无需 Node、Python 或 Docker。适用于 Debian、Ubuntu、CentOS 等主流发行版。"
    }
  ],

  // 提示块
  noticeTitle: "执行前请先确认一件事",
  noticeLines: [
    "如果你打算关闭密码登录，请先用密钥新开一个终端确认能登录，再执行 \`-P yes\`。否则一旦密钥配错，就会失去远程访问。",
    "脚本对 sshd 的每一次改动都会先备份、后校验；校验不通过会自动回滚，并在原会话中保留连接。"
  ],

  // 备用命令（没有 curl 时）
  altTitle: "没有 curl？用 wget",
  altCommands: [
    "wget -qO- {{BASE_URL}} | bash -s -- -c",
    "curl -s {{BASE_URL}}/script.sh | bash -s -- -c"
  ],

  // 页脚
  footerLines: [
    "浏览器访问本页显示说明；curl / wget 访问同一地址返回安装脚本。",
    "公钥来源 {{BASE_URL}}/ssh.keys"
  ]
};

// 下面的东西一般不用改.
const baseRepoPageUrl = `https://${githubUserName.toLowerCase()}.github.io/${githubInstSshProjectName}/`;
const installScriptUrl = `${baseRepoPageUrl}/conf-sshd.sh`;
// 如果出现 Github 无法使用的情况, 可以修改 sshKeyUrl 来变更位置.
// 也可以添加额外的 SSH 公钥地址(比如 KeyBase).
const sshKeyUrls = [
  `https://github.com/${githubUserName}.keys`
];

// 下面是脚本的占位符.
const SCRIPT_PH_SSH_KEY_URL = "{{ SSH_KEY_URL }}"
const SCRIPT_PH_SCRIPT_URL = "{{ SCRIPT_URL }}"
const SCRIPT_PH_DEFAULT_CRON = "{{ DEFAULT_CRON }}"


async function sendScriptContent(baseUrl) {
  let scriptResp = await fetch(new Request(installScriptUrl));
  if (scriptResp.ok) {
    let scriptContent = await scriptResp.text();

    scriptContent = scriptContent.replace(SCRIPT_PH_SSH_KEY_URL, `${baseUrl}/ssh.keys`)
                  .replace(SCRIPT_PH_SCRIPT_URL, `${baseUrl}/script.sh`)
                  .replace(SCRIPT_PH_DEFAULT_CRON, cronExpression)

    return new Response(scriptContent, {
      headers: {
        "content-type": "text/plain; charset=utf-8",
        "cache-control": "no-store"
      }
    });
  } else {
    return new Response("Failed to get install script.", {
      status: 500,
      statusText: "Failed to get install script",
      headers: {
        "content-type": "text/plain; charset=utf-8",
        "cache-control": "no-store"
      }
    });
  }
}

// 把落地页配置里的 {{BASE_URL}} 换成当前访问地址.
function fillBaseUrl(text, baseUrl) {
  return text.split("{{BASE_URL}}").join(baseUrl);
}

// 由配置区生成落地页 HTML（结构固定，内容全部来自 landing）.
function renderLandingPage(baseUrl) {
  const esc = (s) => String(s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

  // 文案支持反引号包住行内代码：`like this`
  const rich = (s) => esc(s).replace(/`([^`]+)`/g, "<code>$1</code>");

  const tabs = landing.commands.map((c, i) =>
    `      <button role="tab" aria-selected="${i === 0 ? "true" : "false"}" data-i="${i}">` +
    `${esc(c.label)}${c.tag ? `<span class="tag">${esc(c.tag)}</span>` : ""}</button>`
  ).join("\n");

  const features = landing.features.map((f) =>
    `    <div class="card">\n      <h3>${esc(f.title)}</h3>\n      <p>${rich(f.body)}</p>\n    </div>`
  ).join("\n");

  const notice = landing.noticeLines.map((l) =>
    `    <p>${rich(l)}</p>`
  ).join("\n");

  const altCommands = landing.altCommands.map((c) =>
    `    <div class="cmd mono"><span class="p">$ </span>${esc(fillBaseUrl(c, baseUrl))}</div>`
  ).join("\n");

  const footer = landing.footerLines.map((l) =>
    `    <div>${esc(fillBaseUrl(l, baseUrl))}</div>`
  ).join("\n");

  const cmdData = JSON.stringify(landing.commands.map((c) => fillBaseUrl(c.cmd, baseUrl)));
  const hintData = JSON.stringify(landing.commands.map((c) => c.hint));
  return `<!DOCTYPE html>
<html lang="${esc(landing.lang)}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="description" content="${esc(landing.description)}">
<title>${esc(landing.title)}</title>
<style>
  :root{
    --bg:#f5f5f7; --surface:#ffffff; --surface-2:#ececef; --text:#1d1d1f; --muted:#6e6e73;
    --muted-strong:#51515a;
    --line:rgba(0,0,0,.10); --accent:#0071e3; --accent-ink:#ffffff; --ok:#1d8a3f;
    --ink-bg:#1d1d1f; --ink-text:#f5f5f7; --ink-muted:#a1a1a6;
    --shadow:0 1px 2px rgba(0,0,0,.05), 0 14px 34px rgba(0,0,0,.09);
    --radius:18px;
  }
  @media (prefers-color-scheme: dark){
    :root{
      --bg:#000000; --surface:#1c1c1e; --surface-2:#2c2c2e; --text:#f5f5f7; --muted:#98989d;
      --muted-strong:#aeaeb2;
      --line:rgba(255,255,255,.14); --accent:#0a84ff; --accent-ink:#ffffff; --ok:#30d158;
      --ink-bg:#2c2c2e; --ink-text:#f2f2f7; --ink-muted:#98989d;
      --shadow:0 1px 2px rgba(0,0,0,.6), 0 18px 44px rgba(0,0,0,.6);
    }
  }
  *{box-sizing:border-box}
  html,body{margin:0;padding:0}
  body{
    background:var(--bg); color:var(--text);
    font:400 16px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text","Helvetica Neue","PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;
    -webkit-font-smoothing:antialiased; text-rendering:optimizeLegibility;
    padding:0 20px 64px;
  }
  .wrap{max-width:760px;margin:0 auto}
  .mono{font-family:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,"Liberation Mono",monospace}

  header{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:28px 0 8px}
  .brand{display:flex;align-items:center;gap:10px;font-size:15px;letter-spacing:-.01em}
  .dot{width:9px;height:9px;border-radius:50%;background:var(--ok);box-shadow:0 0 0 4px rgba(29,138,63,.18)}
  .brand b{font-weight:600}
  .brand span.sub{color:var(--muted)}
  .gh{flex:0 0 auto;font-size:14px;color:var(--muted);text-decoration:none;border:1px solid var(--line);border-radius:999px;padding:6px 13px;transition:color .18s,border-color .18s}
  .gh:hover{color:var(--text);border-color:rgba(0,0,0,.28)}

  h1{font-size:clamp(26px,5.8vw,40px);line-height:1.18;letter-spacing:-.022em;font-weight:600;margin:36px 0 12px;text-wrap:balance}
  .lede{margin:0;color:var(--muted);font-size:17px;line-height:1.55;max-width:36em}

  .deck{margin-top:30px;background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);box-shadow:var(--shadow);padding:18px}
  .seg{display:flex;gap:4px;background:var(--surface-2);border-radius:11px;padding:4px;overflow-x:auto;scrollbar-width:none}
  .seg::-webkit-scrollbar{display:none}
  .seg button{
    flex:1 0 auto;appearance:none;border:0;background:transparent;color:var(--muted-strong);
    font:500 14px/1.2 inherit;padding:9px 14px;border-radius:8px;cursor:pointer;white-space:nowrap;
    transition:background .18s,color .18s,box-shadow .18s;
  }
  .seg button:hover{color:var(--text)}
  .seg button[aria-selected="true"]{background:var(--surface);color:var(--text);box-shadow:0 1px 2px rgba(0,0,0,.14)}
  .seg button:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
  .tag{font-size:11px;font-weight:600;color:var(--accent);margin-left:5px;vertical-align:1px}

  .strip{display:flex;align-items:stretch;gap:10px;margin-top:14px}
  .cmd{
    flex:1 1 auto;min-width:0;background:var(--ink-bg);color:var(--ink-text);
    border-radius:12px;padding:15px 16px;font-size:13.5px;line-height:1.5;
    overflow-x:auto;white-space:nowrap;scrollbar-width:none;
  }
  .cmd::-webkit-scrollbar{display:none}
  .cmd .p{color:var(--ink-muted);user-select:none}
  .cmd.is-scroll{
    -webkit-mask-image:linear-gradient(to right,#000 calc(100% - 26px),transparent);
    mask-image:linear-gradient(to right,#000 calc(100% - 26px),transparent);
  }
  .copy{
    flex:0 0 auto;appearance:none;border:0;background:var(--accent);color:var(--accent-ink);
    font:600 14px/1 inherit;padding:0 20px;border-radius:12px;cursor:pointer;min-width:104px;
    transition:filter .18s,transform .12s;
  }
  .copy:hover{filter:brightness(1.06)}
  .copy:active{transform:scale(.98)}
  .copy:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
  .copy[data-done="1"]{background:var(--ok)}
  .hint{margin:12px 2px 0;font-size:13.5px;color:var(--muted);min-height:20px}
  .sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}

  .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px;margin-top:26px}
  .card{background:var(--surface);border:1px solid var(--line);border-radius:14px;padding:17px 18px}
  .card h3{margin:0 0 7px;font-size:15px;font-weight:600;letter-spacing:-.01em}
  .card p{margin:0;font-size:14px;line-height:1.55;color:var(--muted)}
  .card code,.note code,.lede code,.alt code{
    font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.88em;
    background:var(--surface-2);border-radius:5px;padding:1px 5px;color:var(--text);
  }

  .note{margin-top:26px;border:1px solid var(--line);border-left:3px solid var(--accent);background:var(--surface);border-radius:12px;padding:16px 18px}
  .note h3{margin:0 0 6px;font-size:14px;font-weight:600}
  .note p{margin:0;font-size:14px;line-height:1.6;color:var(--muted)}
  .note p + p{margin-top:8px}

  .alt{margin-top:30px}
  .alt h2{font-size:14px;font-weight:600;margin:0 0 10px;color:var(--muted)}
  .alt .cmd{margin:0}
  .alt .cmd + .cmd{margin-top:8px}

  footer{margin-top:38px;padding-top:18px;border-top:1px solid var(--line);color:var(--muted);font-size:13px;line-height:1.7}
  footer a{color:var(--muted)}

  @media (max-width:640px){
    .seg{flex-wrap:wrap;overflow:visible}
    .seg button{flex:1 1 44%}
  }
  @media (max-width:560px){
    .strip{flex-direction:column}
    .copy{padding:13px 18px}
    .cmd{white-space:pre-wrap;overflow-wrap:anywhere}
    .cmd.is-scroll{-webkit-mask-image:none;mask-image:none}
  }
  @media (prefers-reduced-motion:reduce){*{transition:none!important}}
</style>
</head>
<body>
<div class="wrap">

  <header>
    <div class="brand">
      <span class="dot" aria-hidden="true"></span>
      <b class="mono">${esc(landing.brand)}</b>
      <span class="sub">${esc(landing.brandSub)}</span>
    </div>
    <a class="gh" href="${esc(landing.repoUrl)}">${esc(landing.repoLabel)}</a>
  </header>

  <h1>${esc(landing.headline)}</h1>
  <p class="lede">${rich(landing.lede)}</p>

  <section class="deck" aria-label="${esc(landing.commandedLabel)}">
    <div class="seg" role="tablist" aria-label="${esc(landing.commandTabsLabel)}">
${tabs}
    </div>
    <div class="strip">
      <div class="cmd mono" id="cmd" role="textbox" aria-readonly="true" aria-label="${esc(landing.commandedLabel)}"></div>
      <button class="copy" id="copy" type="button">${esc(landing.copyLabel)}</button>
    </div>
    <p class="hint" id="hint"></p>
    <p class="sr" aria-live="polite" id="live"></p>
  </section>

  <div class="grid">
${features}
  </div>

  <div class="note">
    <h3>${esc(landing.noticeTitle)}</h3>
${notice}
  </div>

  <section class="alt">
    <h2>${esc(landing.altTitle)}</h2>
${altCommands}
  </section>

  <footer>
${footer}
    <div>项目源码 <a href="${esc(landing.repoUrl)}">${esc(landing.repoUrl)}</a></div>
  </footer>

</div>

<script>
(function(){
  var cmds = ${cmdData};
  var hints = ${hintData};
  var copyLabel = ${JSON.stringify(landing.copyLabel)};
  var doneLabel = ${JSON.stringify(landing.copyDoneLabel)};
  var failLabel = ${JSON.stringify(landing.copyFailLabel)};
  var okAnnounce = ${JSON.stringify(landing.copyOkAnnounce)};
  var failAnnounce = ${JSON.stringify(landing.copyFailAnnounce)};
  var tabs = Array.prototype.slice.call(document.querySelectorAll(".seg button"));
  var cmdEl = document.getElementById("cmd");
  var copyBtn = document.getElementById("copy");
  var hintEl = document.getElementById("hint");
  var liveEl = document.getElementById("live");
  var current = 0;
  var timer = null;

  function syncScroll(){
    cmdEl.classList.toggle("is-scroll", cmdEl.scrollWidth > cmdEl.clientWidth + 1);
  }

  function render(i){
    current = i;
    tabs.forEach(function(t, n){ t.setAttribute("aria-selected", n === i ? "true" : "false"); });
    cmdEl.innerHTML = "";
    var p = document.createElement("span");
    p.className = "p";
    p.textContent = "$ ";
    cmdEl.appendChild(p);
    cmdEl.appendChild(document.createTextNode(cmds[i]));
    cmdEl.scrollLeft = 0;
    hintEl.textContent = hints[i] || "";
    syncScroll();
  }

  function flash(ok){
    copyBtn.setAttribute("data-done", ok ? "1" : "0");
    copyBtn.textContent = ok ? doneLabel : failLabel;
    liveEl.textContent = ok ? okAnnounce : failAnnounce;
    if (timer) { clearTimeout(timer); }
    timer = setTimeout(function(){
      copyBtn.removeAttribute("data-done");
      copyBtn.textContent = copyLabel;
    }, 1600);
  }

  function fallbackCopy(text){
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "readonly");
    ta.style.position = "fixed";
    ta.style.top = "-1000px";
    document.body.appendChild(ta);
    ta.select();
    var ok = false;
    try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
    document.body.removeChild(ta);
    return ok;
  }

  function copyText(text, done){
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function(){ done(true); }, function(){ done(fallbackCopy(text)); });
      return;
    }
    done(fallbackCopy(text));
  }

  tabs.forEach(function(t, i){
    t.addEventListener("click", function(){ render(i); });
    t.addEventListener("keydown", function(e){
      var d = e.key === "ArrowRight" ? 1 : (e.key === "ArrowLeft" ? -1 : 0);
      if (!d) { return; }
      e.preventDefault();
      var n = (i + d + tabs.length) % tabs.length;
      tabs[n].focus();
      render(n);
    });
  });

  copyBtn.addEventListener("click", function(){ copyText(cmds[current], flash); });
  window.addEventListener("resize", syncScroll);

  render(0);
})();
</script>
</body>
</html>`;
}

export default {
  async fetch(request, env) {
    const { pathname, host } = new URL(request.url);
    const baseUrl = defaultBaseUrl || `https://${host}`;
    if (pathname === "/ssh.keys") {
      for (let url of sshKeyUrls) {
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
      if (backupSshKeys.length > 0) {
        return new Response(backupSshKeys, {
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
        return await sendScriptContent(baseUrl);
      } else {
        return new Response(renderLandingPage(baseUrl), {
          headers: {
            "content-type": "text/html; charset=utf-8",
            "cache-control": "no-store"
          }
        });
      }
    } else if (pathname === "/script.sh") {
      return await sendScriptContent(baseUrl);
    } else {
      return new Response("Not found.", {
        status: 404,
        statusText: "Not Found"
      })
    }
  }
}
