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

script_params=("$@")
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
    echo "WARNING: 无法自动 reload sshd, 请手动执行: systemctl restart ssh"
    return 0
}

update_sshkeys() {
    if [ "$sshkey_url" == "" ] || [[ "$sshkey_url" == "{{"* ]]; then
        echo "ERROR: sshkey_url is not configured."
        exit 1
    fi

    echo "Downloading SSH public key from '$sshkey_url'"
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    local dl_tmp_file=~/.ssh/authorized_keys.dl.tmp
    if ! curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 "$sshkey_url" -o "$dl_tmp_file"; then
        echo "Failed to download SSH public key at $(date '+%Y-%m-%d %H:%M:%S')"
        rm -f "$dl_tmp_file"
        exit 1
    fi

    if [ ! -s "$dl_tmp_file" ] || ! grep -qE '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp|sk-ssh-ed25519|sk-ecdsa-sha2-nistp)' "$dl_tmp_file"; then
        echo "Downloaded file is empty or does not contain valid SSH key types at $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Aborting update to prevent lockout."
        rm -f "$dl_tmp_file"
        exit 1
    fi

    # 复核: 每一行都必须能被 ssh-keygen 解析, 防止 HTML/文档页骗过上面的类型匹配
    if ! ssh-keygen -lf "$dl_tmp_file" >/dev/null 2>&1; then
        echo "Downloaded content is not a parseable public key list at $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Aborting update to prevent lockout."
        rm -f "$dl_tmp_file"
        exit 1
    fi
    
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
            echo "ERROR: 受管块有 BEGIN 标记但缺少 END 标记, 为避免丢失文件其余内容, 本次跳过更新."
            rm -f "$dl_tmp_file"
            exit 1
        fi
    fi

    touch "$auth_file"
    true > "$new_auth_file"

    while IFS= read -r line; do
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
    echo "SSH public key updated successfully (managed block only) at $(date '+%Y-%m-%d %H:%M:%S')"
}

# 检查是否指定了 --uninstall
if [ "$(has_param "--uninstall")" == "true" ]; then
    echo "Uninstalling conf-sshd (disabling auto-updates)..."
    
    if [ "$(command -v crontab)" != "" ]; then
        echo "Removing Crontab entry..."
        ( (crontab -l 2>/dev/null || true) | grep -F -v "conf-sshd.sh") | crontab -
    else
        echo "Crontab utility not found, skipping Crontab removal."
    fi

    script_dir="$HOME/.conf-sshd"
    if [ -d "$script_dir" ]; then
        echo "Removing script files from $script_dir..."
        rm -rf "$script_dir"
    else
        echo "Script directory $script_dir not found, skipping removal."
    fi

    echo "Uninstall complete."
    echo "Note: authorized_keys managed block and sshd_config were NOT affected."
    exit 0
fi

# 检查是否只更新密钥.
if [ "$(has_param "-o" "--only-update-keys")" == "true" ]; then
    update_sshkeys
    exit 0
fi

# 检查是否指定了 --update-self
if [ "$(has_param "-u" "--update-self")" == "true" ]; then
    echo "Updating conf-sshd script..."
    mkdir -p ~/.conf-sshd
    target_script=~/.conf-sshd/conf-sshd.sh

    if [ -f "$target_script" ]; then
        cp "$target_script" "$target_script.bak"
    fi

    # 下载到临时文件
    if ! curl -sL "$script_url" -o "$target_script.tmp"; then
         echo "Script download failed at $(date '+%Y-%m-%d %H:%M:%S')"
         rm -f "$target_script.tmp"
         exit 1
    fi

    mv "$target_script.tmp" "$target_script"

    chmod +x "$target_script"
    echo "Script updated successfully at $(date '+%Y-%m-%d %H:%M:%S')"
    exit 0
fi

# 检查 SSHD 是否安装.
if ! /usr/sbin/sshd -T > /dev/null 2>&1 && [ "$(has_param "-n" "--no-install-sshd")" == "false" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        echo "The ssh server is not installed, and the script is executed as root, so it will be installed."
        if [ -f /etc/redhat-release ]; then
            yum install -y openssh-server
        elif [ -f /etc/debian_version ]; then
            apt-get update
            apt-get install -y openssh-server
        fi
        echo "The ssh server has been installed."
    else
        echo "The ssh server is not installed, but the script is executed as a non-root user and cannot be installed."
        exit 1
    fi
else
    echo "The ssh server is already installed."
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
            echo "Setting: Root user is allowed to log in with password."
        elif [ "$allow_root_passwd" == "no" ]; then
            new_sshd_permit_root_login_setting="PermitRootLogin prohibit-password"
            echo "Setting: Root user is prohibited from logging in with password."
        else
            echo "Please specify 'yes' or 'no' for --allow-root-passwd."
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
            echo "ERROR: 生成新配置失败, 原文件保持不变."
            rm -f "$sshd_config_file.conf-sshd.new"
            exit 1
        fi

        chmod --reference="$sshd_config_file" "$sshd_config_file.conf-sshd.new" 2>/dev/null || true
        mv "$sshd_config_file.conf-sshd.new" "$sshd_config_file"

        if ! grep -qF "$new_sshd_permit_root_login_setting" "$sshd_config_file"; then
            echo "ERROR: 未能写入 '$new_sshd_permit_root_login_setting', 已回滚."
            cp -a "$sshd_config_file.bak.conf-sshd" "$sshd_config_file"
            exit 1
        fi

        if sshd -t >/dev/null 2>&1; then
            reload_sshd
            echo "SSHD config updated and applied (sshd reloaded)."
        else
            echo "ERROR: 'sshd -t' 校验失败, 已回滚 $sshd_config_file"
            cp -a "$sshd_config_file.bak.conf-sshd" "$sshd_config_file"
            exit 1
        fi

    else
        echo "WARNING: 非 root 用户无法设置 root 的密码登录方式, 已跳过该步骤."
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
            echo "Please specify 'yes' or 'no' for --disable-password-auth."
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
            echo "ERROR: drop-in 写入校验失败, 已撤销 $sshd_dropin_file"
            rm -f "$sshd_dropin_file"
            exit 1
        fi

        if sshd -t >/dev/null 2>&1; then
            reload_sshd
            echo "PasswordAuthentication=$pa_val applied. (drop-in: $sshd_dropin_file)"
            if [ "$pa_val" == "no" ]; then
                echo "NOTE: 先确认已授权的密钥能登录, 再关闭当前会话, 否则将失去远程访问。"
            fi
        else
            echo "ERROR: 'sshd -t' 校验失败, 已撤销 $sshd_dropin_file"
            rm -f "$sshd_dropin_file"
            exit 1
        fi
    else
        echo "WARNING: 非 root 用户无法修改密码认证方式, 已跳过该步骤."
    fi
fi

# 更新密钥.
update_sshkeys

# 检查是否指定了 --cron
if [ "$(has_param "-c" "--cron")" == "true" ]; then
    # 检查 Crontab 是否已安装
    if [ "$(command -v crontab)" == "" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            echo "The crontab is not installed, and the script is executed as a root user, so it will be installed."
            if [ -f /etc/redhat-release ]; then
                yum install -y crontabs
            elif [ -f /etc/debian_version ]; then
                apt-get update
                apt-get install -y cron
            fi
            echo "The crontab has been installed."
        else
            echo "The crontab is not installed, but the script is executed as a non-root user and cannot be installed."
            exit 1
        fi
    else
        echo "The crontab is already installed."
    fi
    cron=$(get_param_value "-c" "--cron" | tr '[:upper:]' '[:lower:]')
    if [ "$cron" == "false" ]; then
        # 检查 Crontab 是否已经设置
        if [ "$( (crontab -l 2>/dev/null || true) | grep -F -c "conf-sshd.sh" )" -eq 0 ]; then
            echo "Crontab already clean. Will not be configured."
            exit 0
        else
            (crontab -l 2>/dev/null || true) | grep -F -v "conf-sshd.sh" | crontab -
            echo "Crontab has been removed."
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
            echo "Downloading conf-sshd script..."
            if ! curl -sL "$script_url" -o "$target_script.tmp"; then
                 echo "Script download failed at $(date '+%Y-%m-%d %H:%M:%S')"
                 rm -f "$target_script.tmp"
                 exit 1
            fi
            mv "$target_script.tmp" "$target_script"
        else 
            echo "Copying conf-sshd script..."
            cp "$0" "$target_script"
        fi
        
        chmod +x "$target_script"
        echo "Install conf-sshd script successfully."
        # 将当前脚本追加到当前用户的 Crontab 中
        echo "Configuring Crontab..."
        cron_command="\"/bin/bash $target_script -o\" >> $HOME/.conf-sshd/run.log 2>&1"
        cron_job="$cron $cron_command"

        ( (crontab -l 2>/dev/null || true) | grep -F -v "conf-sshd.sh") | { cat; echo "$cron_job"; } | crontab -

        echo "Crontab has been configured.(Cron: '$cron')"
    fi
fi
