#!/bin/bash

rm -rf $0

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
  arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
  arch="arm64-v8a"
else
  arch="64"
  echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
    else
        apt update -y
        apt install wget curl unzip tar cron socat -y
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/wand.service ]]; then
        return 2
    fi
    temp=$(systemctl status wand | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

install_wand() {
    if [[ -e /usr/local/wand/ ]]; then
        rm /usr/local/wand/ -rf
    fi

    mkdir /usr/local/wand/ -p
	cd /usr/local/wand/
	
	last_version=$(curl -Ls "https://api.github.com/repos/vmzn/wand-server/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
	if [[ ! -n "$last_version" ]]; then
		echo -e "${red}检测 Wand 版本失败，可能是超出 Github API 限制，请稍后再试${plain}"
		exit 1
	fi
	echo -e "检测到 Wand 最新版本：${last_version}，开始安装"
	wget -N --no-check-certificate -O /usr/local/wand/wand-linux.zip https://github.com/vmzn/wand-server/releases/download/${last_version}/wand-linux-${arch}.zip
	if [[ $? -ne 0 ]]; then
		echo -e "${red}下载 Wand 失败，请确保你的服务器能够下载 Github 的文件${plain}"
		exit 1
	fi

    unzip wand-linux.zip
    rm wand-linux.zip -f
    chmod +x wand
    mkdir /etc/wand/ -p
    rm /etc/systemd/system/wand.service -f
    file="https://raw.githubusercontent.com/vmzn/wand-server/master/wand.service"
    wget -N --no-check-certificate -O /etc/systemd/system/wand.service ${file}
    #cp -f wand.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl stop wand
    systemctl enable wand
    echo -e "${green}wand ${last_version}${plain} 安装完成，已设置开机自启"
    cp geoip.dat /etc/wand/
    cp geosite.dat /etc/wand/ 

    if [[ ! -f /etc/wand/config.yml ]]; then
        cp config.yml /etc/wand/
        echo -e ""
        echo -e "全新安装"
    else
        systemctl start wand
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}Wand 重启成功${plain}"
        else
            echo -e "${red}Wand 可能启动失败，请稍后使用 wand log 查看日志信息${plain}"
        fi
    fi

    if [[ ! -f /etc/wand/dns.json ]]; then
        cp dns.json /etc/wand/
    fi
    if [[ ! -f /etc/wand/route.json ]]; then
        cp route.json /etc/wand/
    fi
    if [[ ! -f /etc/wand/custom_outbound.json ]]; then
        cp custom_outbound.json /etc/wand/
    fi
    curl -o /usr/bin/wand -Ls https://raw.githubusercontent.com/vmzn/wand-server/master/wand.sh
    chmod +x /usr/bin/wand
    ln -s /usr/bin/Wand /usr/bin/wand # 小写兼容
    chmod +x /usr/bin/wand
	
	# 设置服务端域名
    read -p "请输入服务端域名(eg:www.abc.com):" api_host
    [ -z "${api_host}" ]
    echo "---------------------------"
    echo "您设置服务端域名为 ${api_host}"
    echo "---------------------------"
    echo ""
	
	# 设置节服务端密钥
    read -p "请输入服务端密钥:" api_key
    [ -z "${api_key}" ]
    echo "---------------------------"
    echo "您设置节服务端密钥为 ${api_key}"
    echo "---------------------------"
    echo ""
	
	# 设置节点序号
    read -p "请输入节点序号:" node_id
    [ -z "${node_id}" ]
    echo "---------------------------"
    echo "您设置的节点序号为 ${node_id}"
    echo "---------------------------"
    echo ""
	
	# 设置协议
    read -p "请输入节点协议(V2ray, Shadowsocks, Trojan)(默认:V2ray):" node_type
    [ -z "${node_type}" ]
    # 如果不输入默认为V2ray
    if [ ! $node_type ]; then 
    node_type="V2ray"
    fi
	echo "---------------------------"
    echo "您设置的协议为 ${node_type}"
    echo "---------------------------"
    echo ""
	
	# 设置节点域名
    read -p "请输入节点域名(eg:test.abc.com):" cert_domain
    [ -z "${cert_domain}" ]
    echo "---------------------------"
    echo "您设置节点域名为 ${cert_domain}"
    echo "---------------------------"
    echo ""
	
	# 设置SSL
    read -p "请输入SSL认证方式(none, file, http, dns)(默认:http):" cert_mode
    [ -z "${cert_mode}" ]
    # 如果不输入默认为http
    if [ ! $cert_mode ]; then 
    cert_mode="http"
    fi
	echo "---------------------------"
    echo "您设置的SSL认证方式为 ${cert_mode}"
    echo "---------------------------"
    echo ""
	
	if [[ "${cert_mode}" == "http" ]]; then
        domain_check "${cert_domain}"
		port_exist_check 80
    fi
	
	# Writing json
    echo "正在写入配置文件..."
	sed -i "s/ApiHost:.*/ApiHost: \"https:\/\/${api_host}\"/g" /etc/wand/config.yml
	sed -i "s/ApiKey:.*/ApiKey: \"${api_key}\"/g" /etc/wand/config.yml
	sed -i "s/NodeID:.*/NodeID: ${node_id}/g" /etc/wand/config.yml
    sed -i "s/NodeType:.*/NodeType: ${node_type}/g" /etc/wand/config.yml
	sed -i "s/CertMode:.*/CertMode: ${cert_mode}/g" /etc/wand/config.yml
	sed -i "s/CertDomain:.*/CertDomain: \"${cert_domain}\"/g" /etc/wand/config.yml
    echo ""
    echo "写入完成，正在尝试重启Wand服务..."
    echo
	
	wand restart
	
    echo -e ""
    echo "Wand 管理脚本使用方法"
    echo "------------------------------------------"
    echo "wand                    - 显示管理菜单 (功能更多)"
    echo "wand start              - 启动 Wand"
    echo "wand stop               - 停止 Wand"
    echo "wand restart            - 重启 Wand"
    echo "wand status             - 查看 Wand 状态"
    echo "wand enable             - 设置 Wand 开机自启"
    echo "wand disable            - 取消 Wand 开机自启"
    echo "wand log                - 查看 Wand 日志"
    echo "wand update             - 更新 Wand"
    echo "wand config             - 显示配置文件内容"
    echo "wand install            - 安装 Wand"
    echo "wand uninstall          - 卸载 Wand"
    echo "wand version            - 查看 Wand 版本"
    echo "------------------------------------------"
}

domain_check() {
    domain_ip=$(ping "$1" -c 1 | sed '1{s/[^(]*(//;s/).*//;q}')
    echo -e "正在获取 公网ip 信息，请耐心等待"
    local_ip=$(curl -4L https://api64.ipify.org)
    echo -e "域名dns解析IP：${domain_ip}"
    echo -e "本机IP: ${local_ip}"
    sleep 2
    if [[ $(echo "${local_ip}" | tr '.' '+' | bc) -eq $(echo "${domain_ip}" | tr '.' '+' | bc) ]]; then
        echo -e "域名dns解析IP 与 本机IP 匹配"
        sleep 2
    else
        echo -e "请确保域名添加了正确的 A 记录，否则将无法正常使用"
        echo -e "域名dns解析IP 与 本机IP 不匹配 是否继续安装？[y/n]" && read -r install
        case $install in
        [yY][eE][sS] | [yY])
            echo -e "继续安装"
            sleep 2
            ;;
        *)
            echo -e "安装终止"
            exit 2
            ;;
        esac
    fi
}

port_exist_check() {
    if [[ 0 -eq $(lsof -i:"$1" | grep -i -c "listen") ]]; then
        echo -e "$1 端口未被占用"
        sleep 1
    else
        echo -e "检测到 $1 端口被占用，以下为 $1 端口占用信息"
        lsof -i:"$1"
        echo -e "5s 后将尝试自动 kill 占用进程"
        sleep 5
        lsof -i:"$1" | awk '{print $2}' | grep -v "PID" | xargs kill -9
        echo -e "kill 完成"
        sleep 1
    fi
}

echo -e "${green}开始安装${plain}"
install_base
install_wand
