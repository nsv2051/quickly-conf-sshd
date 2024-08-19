#!/bin/bash

########## 一些配置 ##########

# 默认获取 SSH key 的地方，一般是 Github.
sshkey_url="{{ SSH_KEY_URL }}"
# 默认的 Cron 执行计划, 每天凌晨 0 点执行
default_cron="{{ DEFAULT_CRON }}"
# 脚本 Url
script_url="{{ SCRIPT_URL }}"
# 日志文件路径
log_file="$HOME/.conf-sshd/conf-sshd.log"

# 创建日志目录
mkdir -p "$HOME/.conf-sshd"

############ 日志函数 ##########

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $log_file
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 错误: $1" | tee -a $log_file >&2
}

############ 脚本区 ##########

script_params=$*
has_param() {
    for param in $script_params; do
        for tParam in $@; do
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
    for param in $script_params; do
        if [ "$find" == "true" ]; then
            if [[ $param == -* ]]; then
                return
            fi
            echo $param
            return
        fi
        for tParam in $@; do
            if [ "$tParam" == "$param" ]; then
                find=true
                break
            fi
        done
    done
}

# 帮助信息
if [ $(has_param "-h" "--help") == "true" ]; then
    echo "使用方法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help                              显示此帮助信息。"
    echo ""
    echo "任何用户均可使用的选项: "
    echo "  -c, --cron [cron | false]               配置 Crontab 自动更新 SSH 密钥。可以指定 Cron 表达式。如果指定了 false，将自动删除 Crontab 设置。"
    echo ""
    echo "  -o, --only-update-keys                  仅更新 SSH 密钥，不配置 SSH 服务器。"
    echo "  -u, --update-self                       更新此脚本到最新版本。"
    echo ""
    echo "仅当脚本以 root 身份执行时可用的选项:"
    echo "  -n, --no-install-sshd                   不安装 SSH 服务器。"
    echo "  -p, --allow-root-passwd <yes | no>      允许或禁止 root 用户使用密码登录。"
    echo ""
    exit 0
fi

update_sshkeys() {
    if [ "$sshkey_url" == "" ]; then
        log_error "请指定 SSH 公钥的 URL。"
        exit 1
    fi
    log "正在从 '$sshkey_url' 下载 SSH 公钥..."
    mkdir -p ~/.ssh
    local ssh_keys=$(curl -s $sshkey_url)
    if [ $? -ne 0 ] || [ "$ssh_keys" == "" ]; then
        log_error "下载 SSH 公钥失败。"
        exit 1
    fi
    log "-------------------- SSH 密钥 --------------------"
    log "$ssh_keys"
    log "--------------------------------------------------"
    echo "$ssh_keys" > ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    log "SSH 公钥更新成功。"
}

# 检查是否只更新密钥
if [ $(has_param "-o" "--only-update-keys") == "true" ]; then
    update_sshkeys
    exit 0
fi

# 检查是否指定了 --update-self
if [ $(has_param "-u" "--update-self") == "true" ]; then
    log "正在更新 conf-sshd 脚本..."
    cp $0 "$HOME/.conf-sshd/conf-sshd.sh.bak"
    curl -s $script_url > $0 || { cp "$HOME/.conf-sshd/conf-sshd.sh.bak" $0 && log_error "脚本更新失败" && exit 1; }
    chmod +x "$HOME/.conf-sshd/conf-sshd.sh"
    log "脚本更新成功。"
    exit 0
fi

# 检查 /usr/sbin/sshd 是否存在，且 /usr/sbin/sshd 执行后退出代码为 0
/usr/sbin/sshd -T > /dev/null
if [ $? -ne 0 ] && [ $(has_param "-n" "--no-install-sshd") == "false" ]; then
    if [ $(id -u) -eq 0 ]; then
        log "SSH 服务器未安装，脚本以 root 身份运行，将安装 SSH 服务器。"
        if [ -f /etc/redhat-release ]; then
            yum install -y openssh-server
        elif [ -f /etc/debian_version ]; then
            apt-get update
            apt-get install -y openssh-server
        fi
        log "SSH 服务器已安装。"
    else
        log_error "SSH 服务器未安装，但脚本以非 root 用户运行，无法安装。"
        exit 1
    fi
else
    log "SSH 服务器已安装。"
fi

# 检查是否指定了 --allow-root-passwd
if [ $(has_param "-p" "--allow-root-passwd") == "true" ]; then
    if [ $(id -u) -eq 0 ]; then
        allow_root_passwd=$(get_param_value "-p" "--allow-root-passwd" | tr '[:upper:]' '[:lower:]')
        if [ "$allow_root_passwd" == "yes" ]; then
            sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
            log "已允许 root 用户使用密码登录。"
        elif [ "$allow_root_passwd" == "no" ]; then
            sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
            log "已禁止 root 用户使用密码登录。"
        else
            log_error "请指定是否允许 root 用户使用密码登录。"
            exit 1
        fi
        # 重启 SSH 服务以应用更改
        systemctl restart sshd
        log "SSH 服务已重启，配置已应用。"
    else
        log_error "脚本以非 root 用户运行，无法设置是否允许 root 用户使用密码登录。"
        exit 1
    fi
fi

# 更新密钥
update_sshkeys

# 检查是否指定了 --cron
if [ $(has_param "-c" "--cron") == "true" ]; then
    if [ -z "$(command -v crontab)" ]; then
        if [ $(id -u) -eq 0 ]; then
            log "Crontab 未安装，脚本以 root 用户运行，将安装 Crontab。"
            if [ -f /etc/redhat-release ]; then
                yum install -y crontabs
            elif [ -f /etc/debian_version ]; then
                apt-get update
                apt-get install -y cron
            fi
            log "Crontab 已安装。"
        else
            log_error "Crontab 未安装，但脚本以非 root 用户运行，无法安装。"
            exit 1
        fi
    else
        log "Crontab 已安装。"
    fi
    cron=$(get_param_value "-c" "--cron" | tr '[:upper:]' '[:lower:]')
    if [ "$cron" == "false" ]; then
        if [ -z "$(crontab -l | grep "conf-sshd.sh")" ]; then
            log "Crontab 未配置。"
            exit 0
        else
            crontab -l | grep -v "conf-sshd.sh" | crontab -
            log "Crontab 已移除。"
            exit 0
        fi
    else
        [ -z "$cron" ] && cron=$default_cron
        mkdir -p "$HOME/.conf-sshd"
        if [ ! -f $0 ]; then
            log "正在下载 conf-sshd 脚本..."
            curl -o "$HOME/.conf-sshd/conf-sshd.sh" $script_url
        else 
            log "正在复制 conf-sshd 脚本..."
            cp $0 "$HOME/.conf-sshd/conf-sshd.sh"
        fi
        chmod +x "$HOME/.conf-sshd/conf-sshd.sh"
        log "conf-sshd 脚本安装成功。"
        crontab -l > "$HOME/.conf-sshd/crontab.old"
        echo "$cron \"/bin/bash $HOME/.conf-sshd/conf-sshd.sh -o\" >> $HOME/.conf-sshd/run.log" >> "$HOME/.conf-sshd/crontab.old"
        crontab "$HOME/.conf-sshd/crontab.old"
        rm "$HOME/.conf-sshd/crontab.old"
        log "Crontab 已配置。（Cron: '$cron'）"
    fi
fi
