#!/bin/bash
set -e
set -o pipefail

########## 一些配置 ##########

# 默认获取 SSH key 的地方，一般是 Github.
sshkey_url="{{ SSH_KEY_URL }}"
# 默认的 Cron 执行计划, 每天凌晨 0 点执行
default_cron="{{ DEFAULT_CRON }}"
# 脚本 Url
script_url="{{ SCRIPT_URL }}"

############ 脚本区 ##########

# 归一化参数：把 --key=value 拆成 --key value，兼容两种写法。
script_params=()
for _arg in "$@"; do
    case "$_arg" in
        --*=*) script_params+=("${_arg%%=*}" "${_arg#*=}") ;;
        *)     script_params+=("$_arg") ;;
    esac
done
unset _arg
has_param() {
    for param in "${script_params[@]}"; do
        for tParam in "$@"; do
            if [ "$tParam" == "$param" ]; then
                echo "true"
                return
            fi
        done
    done
    echo "false"
}

get_param_value() {
    local find=false
    for param in "${script_params[@]}"; do
        if [ "$find" == "true" ]; then
            if [[ $param == -* ]]; then
                return
            fi

            echo "$param" 
            return
        fi
        for tParam in "$@"; do
            if [ "$tParam" == "$param" ]; then
                find=true
                break
            fi
        done
    done
}

# 帮助信息.
if [ "$(has_param "-h" "--help")" == "true" ]; then
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help                          Print this help message."
    echo ""
    echo "Available to any user: "
    echo "  -c, --cron \"<cron> | false\"       Configure Crontab to automatically update ssh keys."
    echo "                                      Cron expression MUST be quoted (e.g., \"* 0 * * *\")."
    echo "                                      If 'false' is specified, Crontab settings will be deleted."
    echo ""
    echo "  -o, --only-update-keys            Only update SSH keys, do not configure ssh server."
    echo "  -u, --update-self                 Update this script to the latest version."
    echo "  --uninstall                       Uninstall this script (remove cron and local files)."
    echo ""
    echo "only available when the script is executed as root:"
    echo "  -n, --no-install-sshd             Do not install SSH Server."
    echo "  -p, --allow-root-passwd <yes | no>  Allow Root to log in with a password (只改 PermitRootLogin, 不影响 PasswordAuthentication)."
    echo "  -P, --disable-password-auth <yes | no>  Disable password authentication entirely (仅密钥登录; 写 sshd_config.d drop-in 并 reload sshd)."
    echo ""
    exit 0
fi

# reload sshd (reload 不会断开现有连接, 比 restart 安全)
reload_sshd() {
    if systemctl reload ssh 2>/dev/null; then return 0; fi
    if systemctl reload sshd 2>/dev/null; then return 0; fi
    if command -v service >/dev/null 2>&1; then
        if service ssh reload 2>/dev/null; then return 0; fi
        if service sshd reload 2>/dev/null; then return 0; fi
    fi
    echo "[警告] 无法自动 reload sshd, 请手动执行: systemctl restart ssh"
    echo "[WARN] Unable to reload sshd automatically; please run manually: systemctl restart ssh"
    return 0
}

# 输出当前 crontab 中“非本脚本”的行。
# 用子 shell + `|| true` 兜底：grep 无匹配时返回 0，避免 set -e + pipefail 误杀后续流程。
# 匹配精确到脚本自身路径（/.conf-sshd/conf-sshd.sh），避免误删用户无关的注释行。
filter_own_crontab() {
    (crontab -l 2>/dev/null || true) | { grep -F -v "/.conf-sshd/conf-sshd.sh" || true; }
}

update_sshkeys() {
    if [ "$sshkey_url" == "" ] || [[ "$sshkey_url" == "{{"* ]]; then
        echo "[错误] 未配置 sshkey_url."
        echo "[ERROR] sshkey_url is not configured."
        exit 1
    fi

    echo "[执行] 正在从 '$sshkey_url' 下载 SSH 公钥..."
    echo "[RUN] Downloading SSH public key from '$sshkey_url'"
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    local dl_tmp_file=~/.ssh/authorized_keys.dl.tmp
    if ! curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 "$sshkey_url" -o "$dl_tmp_file"; then
        echo "[错误] SSH 公钥下载失败, 时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "[ERROR] Failed to download SSH public key at $(date '+%Y-%m-%d %H:%M:%S')"
        rm -f "$dl_tmp_file"
        exit 1
    fi

    if [ ! -s "$dl_tmp_file" ] || ! grep -qE '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp|sk-ssh-ed25519|sk-ecdsa-sha2-nistp)' "$dl_tmp_file"; then
        echo "[错误] 下载内容为空或不含有效 SSH 公钥类型, 时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "[ERROR] Downloaded file is empty or contains no valid SSH key types at $(date '+%Y-%m-%d %H:%M:%S')"
        echo "[警告] 为防止锁死登录, 已中止更新."
        echo "[WARN] Aborting update to prevent lockout."
        rm -f "$dl_tmp_file"
        exit 1
    fi

    # 复核: 逐行校验, 忽略空行与注释行; 每一条非空非注释行都必须是可解析的公钥.
    # 仅整体 `ssh-keygen -lf` 会漏过"有效key+垃圾行"的混合内容.
    local valid_key_count=0
    while IFS= read -r kline || [ -n "$kline" ]; do
        case "$kline" in
            ''|'#'*) continue ;;
        esac
        if ! printf '%s\n' "$kline" | ssh-keygen -lf - >/dev/null 2>&1; then
            echo "[错误] 下载内容包含非公钥行, 时间: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "[ERROR] Downloaded content contains a non-key line at $(date '+%Y-%m-%d %H:%M:%S')"
            echo "[警告] 为防止锁死登录, 已中止更新."
            echo "[WARN] Aborting update to prevent lockout."
            rm -f "$dl_tmp_file"
            exit 1
        fi
        valid_key_count=$((valid_key_count + 1))
    done < "$dl_tmp_file"

    if [ "$valid_key_count" -lt 1 ]; then
        echo "[错误] 下载内容没有可用的公钥, 时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "[ERROR] Downloaded content has no usable public key at $(date '+%Y-%m-%d %H:%M:%S')"
        echo "[警告] 为防止锁死登录, 已中止更新."
        echo "[WARN] Aborting update to prevent lockout."
        rm -f "$dl_tmp_file"
        exit 1
    fi
    
    echo "[信息] 即将写入的 SSH 公钥如下:"
    echo "[INFO] SSH public keys to be installed:"
    echo "-------------------- SSH Keys --------------------"
    cat "$dl_tmp_file"
    echo "--------------------------------------------------"
    
    local auth_file=~/.ssh/authorized_keys
    local new_auth_file=~/.ssh/authorized_keys.new.tmp
    
    # 受管理文本块标记
    local begin_marker="# --- BEGIN MANAGED BY CONF-SSHD SCRIPT ---"
    local end_marker="# --- END MANAGED BY CONF-SSHD SCRIPT ---"

    local managed_block_found=false
    local inside_managed_block=false

    # 安全护栏: 旧逻辑在"有 BEGIN 却缺 END"时会把 BEGIN 之后到文件末尾的内容全部丢弃
    if grep -qF "$begin_marker" "$auth_file"; then
        if ! awk -v bm="$begin_marker" -v em="$end_marker" '
                index($0, bm) { seen = 1 }
                seen && index($0, em) { ok = 1 }
                END { exit (ok ? 0 : 1) }
            ' "$auth_file"; then
            echo "[错误] 受管块有 BEGIN 标记但缺少 END 标记, 为避免丢失文件其余内容, 本次跳过更新."
            echo "[ERROR] Managed block has a BEGIN marker but no END marker; skipping this update to avoid losing the rest of the file."
            rm -f "$dl_tmp_file"
            exit 1
        fi
    fi

    touch "$auth_file"
    true > "$new_auth_file"

    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$line" == "$begin_marker" ]; then
            managed_block_found=true
            inside_managed_block=true
            
            {
                echo "$begin_marker"
                cat "$dl_tmp_file"
                echo "$end_marker"
            } >> "$new_auth_file"
            
        elif [ "$line" == "$end_marker" ]; then
            inside_managed_block=false
        elif [ "$inside_managed_block" == "false" ]; then
            echo "$line" >> "$new_auth_file"
        fi
    done < "$auth_file"

    if [ "$managed_block_found" == "false" ]; then
        if [ -s "$new_auth_file" ]; then
            if [ "$(tail -c 1 "$new_auth_file")" != "" ]; then
                # 最后一个字符不是换行符，添加一个
                echo "" >> "$new_auth_file"
            fi
        fi
        
        {
            echo "$begin_marker"
            cat "$dl_tmp_file"
            echo "$end_marker"
        } >> "$new_auth_file"
    fi

    # 覆盖前备份, 便于事后比对/回滚
    if [ -s "$auth_file" ]; then
        cp -a "$auth_file" "$auth_file.bak"
    fi

    mv "$new_auth_file" "$auth_file"
    rm -f "$dl_tmp_file"

    chmod 600 "$auth_file"
    echo "[完成] SSH 公钥更新成功 (仅受管块), 时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "[DONE] SSH public key updated successfully (managed block only) at $(date '+%Y-%m-%d %H:%M:%S')"
}

# 检查是否指定了 --uninstall
if [ "$(has_param "--uninstall")" == "true" ]; then
    echo "[执行] 正在卸载 conf-sshd (关闭自动更新)..."
    echo "[RUN] Uninstalling conf-sshd (disabling auto-updates)..."
    
    if [ "$(command -v crontab)" != "" ]; then
        echo "[执行] 正在移除 Crontab 条目..."
        echo "[RUN] Removing Crontab entry..."
        filter_own_crontab | crontab -
    else
        echo "[警告] 未找到 crontab 工具, 跳过 Crontab 移除."
        echo "[WARN] Crontab utility not found; skipping Crontab removal."
    fi

    script_dir="$HOME/.conf-sshd"
    if [ -d "$script_dir" ]; then
        echo "[执行] 正在移除脚本文件: $script_dir ..."
        echo "[RUN] Removing script files from $script_dir ..."
        rm -rf "$script_dir"
    else
        echo "[警告] 未找到脚本目录 $script_dir, 跳过移除."
        echo "[WARN] Script directory $script_dir not found; skipping removal."
    fi

    echo "[完成] 卸载完成."
    echo "[DONE] Uninstall complete."
    echo "[提示] 未改动 authorized_keys 受管块与 sshd_config."
    echo "[NOTE] The authorized_keys managed block and sshd_config were NOT affected."
    exit 0
fi

# 检查是否只更新密钥.
if [ "$(has_param "-o" "--only-update-keys")" == "true" ]; then
    update_sshkeys
    exit 0
fi

# 检查是否指定了 --update-self
if [ "$(has_param "-u" "--update-self")" == "true" ]; then
    echo "[执行] 正在更新 conf-sshd 脚本..."
    echo "[RUN] Updating conf-sshd script..."
    mkdir -p ~/.conf-sshd
    target_script=~/.conf-sshd/conf-sshd.sh

    if [ -f "$target_script" ]; then
        cp "$target_script" "$target_script.bak"
    fi

    # 下载到临时文件（-f：HTTP 错误时直接失败，避免把错误页当脚本落盘）
    if ! curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 "$script_url" -o "$target_script.tmp"; then
         echo "[错误] 脚本下载失败, 时间: $(date '+%Y-%m-%d %H:%M:%S')"
         echo "[ERROR] Script download failed at $(date '+%Y-%m-%d %H:%M:%S')"
         rm -f "$target_script.tmp"
         exit 1
    fi

    # 校验内容确实像本脚本，避免把 HTML/错误页覆盖到正在使用的脚本上
    if ! grep -qE 'sshkey_url|conf-sshd' "$target_script.tmp"; then
         echo "[错误] 下载内容不像 conf-sshd 脚本, 已中止."
         echo "[ERROR] Downloaded content does not look like the conf-sshd script. Aborting."
         rm -f "$target_script.tmp"
         exit 1
    fi

    mv "$target_script.tmp" "$target_script"

    chmod +x "$target_script"
    echo "[完成] 脚本自更新成功, 时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "[DONE] Script updated successfully at $(date '+%Y-%m-%d %H:%M:%S')"
    exit 0
fi

# 检查 SSHD 是否安装.
if ! /usr/sbin/sshd -T > /dev/null 2>&1 && [ "$(has_param "-n" "--no-install-sshd")" == "false" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        echo "[执行] 未检测到 SSH 服务, 当前以 root 运行, 将自动安装."
        echo "[RUN] SSH server is not installed; running as root, so it will be installed."
        if [ -f /etc/redhat-release ]; then
            yum install -y openssh-server
        elif [ -f /etc/debian_version ]; then
            apt-get update
            apt-get install -y openssh-server
        fi
        echo "[完成] SSH 服务安装完成."
        echo "[DONE] SSH server installed successfully."
    else
        echo "[错误] 未检测到 SSH 服务, 且当前为非 root 用户, 无法安装."
        echo "[ERROR] SSH server is not installed and the script runs as a non-root user, so it cannot be installed."
        exit 1
    fi
else
    if /usr/sbin/sshd -T > /dev/null 2>&1; then
        echo "[信息] SSH 服务已安装."
        echo "[INFO] SSH server is already installed."
    else
        echo "[信息] 未安装 SSH 服务, 已按 '-n' 跳过安装."
        echo "[INFO] SSH server is not installed; installation skipped ('-n' specified)."
    fi
fi

# 检查是否指定了 --allow-root-passwd
if [ "$(has_param "-p" "--allow-root-passwd")" == "true" ]; then
    # 检查当前用户是否为 root
    if [ "$(id -u)" -eq 0 ]; then
        allow_root_passwd=$(get_param_value "-p" "--allow-root-passwd" | tr '[:upper:]' '[:lower:]')
        
        sshd_config_file="/etc/ssh/sshd_config"
        new_sshd_permit_root_login_setting=""

        if [ "$allow_root_passwd" == "yes" ]; then
            new_sshd_permit_root_login_setting="PermitRootLogin yes"
            echo "[信息] 已设置: 允许 root 用户使用密码登录."
            echo "[INFO] Setting: Root user is allowed to log in with password."
        elif [ "$allow_root_passwd" == "no" ]; then
            new_sshd_permit_root_login_setting="PermitRootLogin prohibit-password"
            echo "[信息] 已设置: 禁止 root 用户使用密码登录."
            echo "[INFO] Setting: Root user is prohibited from logging in with password."
        else
            echo "[错误] 请为 --allow-root-passwd 指定 'yes' 或 'no'."
            echo "[ERROR] Please specify 'yes' or 'no' for --allow-root-passwd."
            exit 1
        fi

        cp -a "$sshd_config_file" "$sshd_config_file.bak.conf-sshd" 2>/dev/null || true

        # 用 awk 重写首个匹配行; 若无匹配行则追加 (不依赖 sed 的方言与 -i 语义)
        awk -v val="$new_sshd_permit_root_login_setting" '
            /^[[:space:]]*#?[[:space:]]*PermitRootLogin/ && done == 0 { print val; done = 1; next }
            { print }
            END { if (done == 0) print val }
        ' "$sshd_config_file" > "$sshd_config_file.conf-sshd.new"

        if [ ! -s "$sshd_config_file.conf-sshd.new" ]; then
            echo "[错误] 生成新配置失败, 原文件保持不变."
            echo "[ERROR] Failed to generate new config; the original file is left unchanged."
            rm -f "$sshd_config_file.conf-sshd.new"
            exit 1
        fi

        chmod --reference="$sshd_config_file" "$sshd_config_file.conf-sshd.new" 2>/dev/null || true
        mv "$sshd_config_file.conf-sshd.new" "$sshd_config_file"

        if ! grep -qF "$new_sshd_permit_root_login_setting" "$sshd_config_file"; then
            echo "[错误] 未能写入 '$new_sshd_permit_root_login_setting', 已回滚."
            echo "[ERROR] Failed to write '$new_sshd_permit_root_login_setting'; rolled back."
            cp -a "$sshd_config_file.bak.conf-sshd" "$sshd_config_file"
            exit 1
        fi

        if sshd -t >/dev/null 2>&1; then
            reload_sshd
            # `sshd -t` 只验语法。用 `sshd -T` 核对实际生效值, 防止被更高优先级的 drop-in 覆盖后仍谎报成功。
            expected_prl=$(printf '%s' "$new_sshd_permit_root_login_setting" | awk '{print tolower($2)}')
            effective_prl=$(sshd -T 2>/dev/null | awk 'tolower($1)=="permitrootlogin"{print tolower($2); exit}')
            if [ "$effective_prl" != "$expected_prl" ]; then
                echo "[错误] PermitRootLogin 未生效 (期望 '$expected_prl', 实际 '${effective_prl:-未知}')。可能被 /etc/ssh/sshd_config.d/ 下的 drop-in 覆盖。"
                echo "[ERROR] PermitRootLogin did not take effect (expected '$expected_prl', actual '${effective_prl:-unknown}'). It may be overridden by a drop-in under /etc/ssh/sshd_config.d/."
                echo "[信息] 已回滚 $sshd_config_file"
                echo "[INFO] Rolled back $sshd_config_file"
                cp -a "$sshd_config_file.bak.conf-sshd" "$sshd_config_file"
                reload_sshd
                exit 1
            fi
            echo "[完成] SSHD 配置已更新并生效 (sshd 已 reload 并校验通过)."
            echo "[DONE] SSHD config updated and applied (sshd reloaded, verified)."
        else
            echo "[错误] 'sshd -t' 校验失败, 已回滚 $sshd_config_file"
            echo "[ERROR] 'sshd -t' validation failed; rolled back $sshd_config_file"
            cp -a "$sshd_config_file.bak.conf-sshd" "$sshd_config_file"
            exit 1
        fi

    else
        echo "[警告] 非 root 用户无法设置 root 的密码登录方式, 已跳过该步骤."
        echo "[WARN] A non-root user cannot change root's password login; step skipped."
    fi
fi

# 检查是否指定了 --disable-password-auth (关闭密码认证, 仅允许密钥登录)
if [ "$(has_param "-P" "--disable-password-auth")" == "true" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        dp_arg=$(get_param_value "-P" "--disable-password-auth" | tr '[:upper:]' '[:lower:]')

        if [ "$dp_arg" == "yes" ]; then
            pa_val="no"
        elif [ "$dp_arg" == "no" ]; then
            pa_val="yes"
        else
            echo "[错误] 请为 --disable-password-auth 指定 'yes' 或 'no'."
            echo "[ERROR] Please specify 'yes' or 'no' for --disable-password-auth."
            exit 1
        fi

        sshd_dropin_dir="/etc/ssh/sshd_config.d"
        sshd_dropin_file="$sshd_dropin_dir/50-disable-password.conf"
        mkdir -p "$sshd_dropin_dir"
        if [ -f "$sshd_dropin_file" ]; then
            cp -a "$sshd_dropin_file" "$sshd_dropin_file.bak.conf-sshd"
        fi

        {
            echo "# Managed by conf-sshd.sh --disable-password-auth"
            echo "PasswordAuthentication $pa_val"
            echo "KbdInteractiveAuthentication $pa_val"
            echo "ChallengeResponseAuthentication $pa_val"
            echo "PermitEmptyPasswords no"
        } > "$sshd_dropin_file"

        if ! grep -qF "PasswordAuthentication $pa_val" "$sshd_dropin_file"; then
            echo "[错误] drop-in 写入校验失败, 已撤销 $sshd_dropin_file"
            echo "[ERROR] drop-in write verification failed; reverted $sshd_dropin_file"
            rm -f "$sshd_dropin_file"
            exit 1
        fi

        if sshd -t >/dev/null 2>&1; then
            reload_sshd
            # `sshd -t` 只验语法。用 `sshd -T` 核对实际生效值，防止“报告成功但配置未生效”。
            effective_pa=$(sshd -T 2>/dev/null | awk 'tolower($1)=="passwordauthentication"{print tolower($2); exit}')
            if [ "$effective_pa" != "$pa_val" ]; then
                echo "[错误] 配置未生效 (期望 PasswordAuthentication=$pa_val, 实际='${effective_pa:-未知}')."
                echo "[ERROR] Config did not take effect (expected PasswordAuthentication=$pa_val, actual='${effective_pa:-unknown}')."
                if ! grep -qiE '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d' /etc/ssh/sshd_config 2>/dev/null; then
                    echo "[提示] /etc/ssh/sshd_config 未 Include sshd_config.d/*.conf, drop-in 不会生效, 请先补上 Include 行。"
                    echo "[NOTE] /etc/ssh/sshd_config does not Include sshd_config.d/*.conf, so the drop-in will not take effect; add the Include line first."
                fi
                echo "[信息] 已撤销 $sshd_dropin_file 并重新加载 sshd。"
                echo "[INFO] Reverted $sshd_dropin_file and reloaded sshd."
                rm -f "$sshd_dropin_file"
                reload_sshd
                exit 1
            fi
            echo "[完成] PasswordAuthentication=$pa_val 已生效并校验通过. (drop-in: $sshd_dropin_file)"
            echo "[DONE] PasswordAuthentication=$pa_val applied and verified. (drop-in: $sshd_dropin_file)"
            if [ "$pa_val" == "no" ]; then
                echo "[提示] 先确认已授权的密钥能登录, 再关闭当前会话, 否则将失去远程访问。"
                echo "[NOTE] Verify an authorized key can log in before closing this session, or you may lose remote access."
            fi
        else
            echo "[错误] 'sshd -t' 校验失败, 已撤销 $sshd_dropin_file"
            echo "[ERROR] 'sshd -t' validation failed; reverted $sshd_dropin_file"
            rm -f "$sshd_dropin_file"
            exit 1
        fi
    else
        echo "[警告] 非 root 用户无法修改密码认证方式, 已跳过该步骤."
        echo "[WARN] A non-root user cannot change password authentication; step skipped."
    fi
fi

# 更新密钥.
update_sshkeys

# 运行日志体积上限：超过 1MiB 时保留末尾 256KiB，避免长期运行无限增长。
trim_run_log() {
    local log_file="$HOME/.conf-sshd/run.log"
    [ -f "$log_file" ] || return 0
    local size
    size=$(wc -c < "$log_file" 2>/dev/null || echo 0)
    if [ "${size:-0}" -gt 1048576 ]; then
        tail -c 262144 "$log_file" > "$log_file.tmp" 2>/dev/null && mv "$log_file.tmp" "$log_file"
    fi
    return 0
}
trim_run_log

# 检查是否指定了 --cron
if [ "$(has_param "-c" "--cron")" == "true" ]; then
    # 检查 Crontab 是否已安装
    if [ "$(command -v crontab)" == "" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            echo "[执行] 未检测到 crontab, 当前以 root 运行, 将自动安装."
            echo "[RUN] crontab is not installed; running as root, so it will be installed."
            if [ -f /etc/redhat-release ]; then
                yum install -y crontabs
            elif [ -f /etc/debian_version ]; then
                apt-get update
                apt-get install -y cron
            fi
            echo "[完成] crontab 安装完成."
            echo "[DONE] crontab installed successfully."
        else
            echo "[错误] 未检测到 crontab, 且当前为非 root 用户, 无法安装."
            echo "[ERROR] crontab is not installed and the script runs as a non-root user, so it cannot be installed."
            exit 1
        fi
    else
        echo "[信息] crontab 已安装."
        echo "[INFO] crontab is already installed."
    fi
    cron=$(get_param_value "-c" "--cron" | tr '[:upper:]' '[:lower:]')
    if [ "$cron" == "false" ]; then
        # 检查 Crontab 是否已经设置
        if [ -z "$( (crontab -l 2>/dev/null || true) | { grep -F "/.conf-sshd/conf-sshd.sh" || true; } )" ]; then
            echo "[信息] Crontab 已处于干净状态, 无需配置."
            echo "[INFO] Crontab is already clean; nothing to configure."
            exit 0
        else
            filter_own_crontab | crontab -
            echo "[完成] Crontab 已移除."
            echo "[DONE] Crontab has been removed."
            exit 0
        fi
    else
        if [ "$cron" == "" ]; then
            cron=$default_cron
        fi
        # 将当前脚本移动到 ~/.conf-sshd/conf-sshd.sh 中.
        mkdir -p ~/.conf-sshd
        target_script=~/.conf-sshd/conf-sshd.sh
        if [ ! -f "$0" ]; then
            echo "[执行] 正在下载 conf-sshd 脚本..."
            echo "[RUN] Downloading conf-sshd script..."
            if ! curl -sL "$script_url" -o "$target_script.tmp"; then
                 echo "[错误] 脚本下载失败, 时间: $(date '+%Y-%m-%d %H:%M:%S')"
                 echo "[ERROR] Script download failed at $(date '+%Y-%m-%d %H:%M:%S')"
                 rm -f "$target_script.tmp"
                 exit 1
            fi
            mv "$target_script.tmp" "$target_script"
        else 
            echo "[执行] 正在复制 conf-sshd 脚本..."
            echo "[RUN] Copying conf-sshd script..."
            cp "$0" "$target_script"
        fi
        
        chmod +x "$target_script"
        echo "[完成] conf-sshd 脚本安装成功."
        echo "[DONE] conf-sshd script installed successfully."
        # 将当前脚本追加到当前用户的 Crontab 中
        echo "[执行] 正在配置 Crontab..."
        echo "[RUN] Configuring Crontab..."
        cron_command="/bin/bash \"$target_script\" -o >> $HOME/.conf-sshd/run.log 2>&1"
        cron_job="$cron $cron_command"

        { filter_own_crontab; echo "$cron_job"; } | crontab -

        echo "[完成] Crontab 配置完成. (Cron: '$cron')"
        echo "[DONE] Crontab configured. (Cron: '$cron')"
    fi
fi
