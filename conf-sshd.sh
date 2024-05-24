#!/bin/bash

########## 一些配置 ##########

# 默认获取 SSH key 的地方，一般是 Github.
sshkey_url="{{ SSH_KEY_URL }}"
# 默认的 Cron 执行计划, 每天凌晨 0 点执行
default_cron="{{ DEFAULT_CRON }}"
# 脚本 Url
script_url="{{ SCRIPT_URL }}"
# 日志文件
log_file="$HOME/.conf-sshd/conf-sshd.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $log_file
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a $log_file >&2
}

############ 脚本区 ##########

script_params=$*
has_param() {
    for param in $script_params; do
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
    for param in $script_params; do
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

# 帮助信息
if [ $(has_param "-h" "--help") == "true" ]; then
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help                              Print this help message."
    echo ""
    echo "Available to any user: "
    echo "  -c, --cron [cron | false]               Configure Crontab to automatically update ssh keys,"
    echo "                                          Cron expression can be specified, If false is specified, "
    echo "                                          Crontab settings will be deleted automatically."
    echo ""
    echo "  -o, --only-update-keys                  Only update SSH keys, do not configure ssh server."
    echo "  -u, --update-self                       Update this script to the latest version."
    echo ""
    echo "only available when the script is executed as root:"
    echo "  -n, --no-install-sshd                   Do not install SSH Server."
    echo "  -p, --allow-root-passwd <yes | no>      Allow Root to log in with a password."
    echo ""
    exit 0
fi

update_sshkeys() {
    if [ -z "$sshkey_url" ]; then
        log_error "SSH public key URL is not specified."
        exit 1
    fi
    log "Downloading SSH public key from '$sshkey_url'"
    mkdir -p ~/.ssh
    local ssh_keys=$(curl -s $sshkey_url)
    if [ $? -ne 0 ] || [ -z "$ssh_keys" ]; then
        log_error "Failed to download SSH public key."
        exit 1
    fi
    echo "$ssh_keys" > ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    log "SSH public key updated successfully."
}

# 检查是否只更新密钥.
if [ $(has_param "-o" "--only-update-keys") == "true" ]; then
    update_sshkeys
    exit 0
fi

# 检查是否指定了 --update-self
if [ $(has_param "-u" "--update-self") == "true" ]; then
    log "Updating conf-sshd script..."
    tmp_file=$(mktemp)
    if curl -s $script_url -o "$tmp_file"; then
        mv "$tmp_file" "$0"
        chmod +x "$0"
        log "Script updated successfully."
    else
        log_error "Script update failed."
        rm -f "$tmp_file"
        exit 1
    fi
    exit 0
fi

# 检查 /usr/sbin/sshd 是否存在，且 /usr/sbin/sshd 执行后退出代码为 0
/usr/sbin/sshd -T > /dev/null 2>&1
if [ $? -ne 0 ] && [ $(has_param "-n" "--no-install-sshd") == "false" ]; then
    if [ $(id -u) -eq 0 ]; then
        log "The ssh server is not installed, and the script is executed as root, so it will be installed."
        if [ -f /etc/redhat-release ]; then
            yum install -y openssh-server
        elif [ -f /etc/debian_version ]; then
            apt-get update
            apt-get install -y openssh-server
        fi
        log "The ssh server has been installed."
    else
        log_error "The ssh server is not installed, but the script is executed as a non-root user and cannot be installed."
        exit 1
    fi
else
    log "The ssh server is already installed."
fi

# 检查是否指定了 --allow-root-passwd
if [ $(has_param "-p" "--allow-root-passwd") == "true" ]; then
    # 检查当前用户是否为 root
    if [ $(id -u) -eq 0 ]; then
        # 获取参数值
        allow_root_passwd=$(get_param_value "-p" "--allow-root-passwd" | tr '[:upper:]' '[:lower:]')
        if [ "$allow_root_passwd" == "yes" ]; then
            # 设置允许 root 使用密码登录
            sed -i 's/^#?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
            log "Root user is allowed to log in with password."
        elif [ "$allow_root_passwd" == "no" ]; then
            # 设置禁止 root 使用密码登录
            sed -i 's/^#?PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
            log "Root user is prohibited from logging in with password."
        else
            log_error "Please specify whether to allow root to log in with a password."
            exit 1
        fi
    else
        log_error "The script is executed as a non-root user and cannot set whether to allow root to log in with a password."
        exit 1
    fi
fi

# 更新密钥
update_sshkeys

# 检查是否指定了 --cron
if [ $(has_param "-c" "--cron") == "true" ]; then
    # 检查 Crontab 是否已安装
    if [ -z "$(command -v crontab)" ]; then
        if [ $(id -u) -eq 0 ]; then
            log "The crontab is not installed, and the script is executed as a root user, so it will be installed."
            if [ -f /etc/redhat-release ]; then
                yum install -y crontabs
            elif [ -f /etc/debian_version ]; then
                apt-get update
                apt-get install -y cron
            fi
            log "The crontab has been installed."
        else
            log_error "The crontab is not installed, but the script is executed as a non-root user and cannot be installed."
            exit 1
        fi
    else
        log "The crontab is already installed."
    fi
    cron=$(get_param_value "-c" "--cron" | tr '[:upper:]' '[:lower:]')
    if [ "$cron" == "false" ]; then
        # 检查 Crontab 是否已经设置
        if [ -z "$(crontab -l | grep "conf-sshd.sh")" ]; then
            log "Crontab will not be configured."
            exit 0
        else
            crontab -l | grep -v "conf-sshd.sh" | crontab -
            log "Crontab has been removed."
            exit 0
        fi
    else
        [ -z "$cron" ] && cron=$default_cron
        # 将当前脚本移动到 ~/.conf-sshd/conf-sshd.sh 中
        mkdir -p ~/.conf-sshd
        if [ ! -f $0 ]; then
            log "Downloading conf-sshd script..."
            curl -o ~/.conf-sshd/conf-sshd.sh $script_url
        else 
            log "Copying conf-sshd script..."
            cp $0 ~/.conf-sshd/conf-sshd.sh
        fi
        chmod +x ~/.conf-sshd/conf-sshd.sh
        log "Install conf-sshd script successfully."
        # 将当前脚本追加到当前用户的 Crontab 中
        crontab -l > ~/.conf-sshd/crontab.old
        echo "$cron /bin/bash ~/.conf-sshd/conf-sshd.sh -o >> ~/.conf-sshd/run.log 2>&1" >> ~/.conf-sshd/crontab.old
        crontab ~/.conf-sshd/crontab.old
        rm ~/.conf-sshd/crontab.old
        log "Crontab has been configured. (Cron: '$cron')"
    fi
fi
