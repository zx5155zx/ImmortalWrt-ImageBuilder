#!/bin/bash
# Log file for debugging
source shell/custom-packages.sh
source shell/switch_repository.sh
echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
echo "编译固件大小为: $PROFILE MB"
echo "Include Docker: $INCLUDE_DOCKER"

echo "Create pppoe-settings"
mkdir -p  /home/build/immortalwrt/files/etc/config

# 创建pppoe配置文件 yml传入环境变量ENABLE_PPPOE等 写入配置文件 供99-custom.sh读取
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择 任何第三方软件包"
else
  # ============= 同步第三方插件库==============
  # 正在同步第三方软件仓库
  echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
  git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

  # 拷贝 run/x86 下所有 run 文件和ipk文件 到 extra-packages 目录
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-run-repo/run/x86/* /home/build/immortalwrt/extra-packages/

  echo "✅ Run files copied to extra-packages:"
  ls -lh /home/build/immortalwrt/extra-packages/*.run
  # 解压并拷贝ipk到packages目录
  sh shell/prepare-packages.sh
  ls -lah /home/build/immortalwrt/packages/
fi

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建..."
# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""
# 基础工具
PACKAGES="$PACKAGES curl wget ca-certificates unzip coreutils-nohup bash"
# iStore商店全套
PACKAGES="$PACKAGES istore istore-webui istore-file luci-app-store luci-i18n-store-zh-cn"
# 系统磁盘/防火墙汉化
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-i18n-filebrowser-zh-cn"
# 定时重启
PACKAGES="$PACKAGES luci-app-autoreboot luci-i18n-autoreboot-zh-cn"
# 主题
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-opkg-zh-cn"
# 网页终端
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
# SSH
PACKAGES="$PACKAGES openssh-sftp-server"

# ========== 新增：网速监控+带宽控制 ==========
# 流量统计
PACKAGES="$PACKAGES luci-app-nlbwmon nlbwmon luci-i18n-nlbwmon-zh-cn"
# 实时全系统监控
PACKAGES="$PACKAGES luci-app-netdata netdata"
# QoS网速限速、缓冲优化
PACKAGES="$PACKAGES luci-app-sqm sqm-scripts luci-i18n-sqm-zh-cn"
# 一键测速
PACKAGES="$PACKAGES luci-app-netspeedtest"
# 终端设备流量排行
PACKAGES="$PACKAGES luci-app-wrtbwmon wrtbwmon"

# ========== Passwall 代理全套 ==========
PACKAGES="$PACKAGES xray-core hysteria luci-app-passwall passwall2 luci-i18n-passwall-zh-cn"

# ========== OpenClash 全套+依赖 ==========
PACKAGES="$PACKAGES luci-app-openclash dnsmasq-full ipset ip-full kmod-tun kmod-nft-tproxy ruby ruby-yaml"

# 首页代理
PACKAGES="$PACKAGES luci-i18n-homeproxy-zh-cn"

# ======== shell/custom-packages.sh =======
# 合并imm仓库以外的第三方插件
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# 若构建openclash 则添加内核（修复绝对路径+增加30秒超时防卡死）
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p /home/build/immortalwrt/files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64-v1.tar.gz"
    wget -q -T 30 $META_URL | tar xOvz > /home/build/immortalwrt/files/etc/openclash/core/clash_meta
    chmod +x /home/build/immortalwrt/files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
    wget -q -T 30 https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O /home/build/immortalwrt/files/etc/openclash/GeoIP.dat
    wget -q -T 30 https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O /home/build/immortalwrt/files/etc/openclash/GeoSite.dat
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$PROFILE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
