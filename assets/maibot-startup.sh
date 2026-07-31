#!/bin/bash

MAIBOT_APP_VERSION="{{VERSION}}"
export UV_LINK_MODE=copy

# 网络重试计数器（持久化到文件，跨 PTY 重启保持计数）
NET_RETRY_FILE="$TMPDIR/.network_retry_count"
MAX_NETWORK_RETRY=3

# 事务完成标记（用于原子性恢复判断）
RESTORE_MARKER="$TMPDIR/.restore_complete"

# 正常退出清理临时解压目录；失败时写错误描述
cleanup_on_exit(){
  RET=$?
  rm -rf "$TMPDIR/backup_restore"
  if [ $RET -ne 0 ]; then
    echo "安装失败，请查看日志" > "$TMPDIR/progress_des"
  fi
}
trap cleanup_on_exit EXIT

# 自定义 Git Clone 命令（为空时使用默认逻辑）
CUSTOM_GIT_CLONE=""

if [ -z "$TMPDIR" ]; then
  echo "错误：未检测到 TMPDIR，请在挂载共享目录时传入 TMPDIR"
  exit 1
fi

if [ ! -d "$TMPDIR" ]; then
  echo "错误：临时目录 $TMPDIR 不存在，请确认挂载已经完成"
  exit 1
fi


progress_echo(){
  echo -e "\033[31m- $@\033[0m"
  echo "$@" > "$TMPDIR/progress_des"
}

bump_progress(){
  current=0
  if [ -f "$TMPDIR/progress" ]; then
    current=$(cat "$TMPDIR/progress" 2>/dev/null || echo 0)
  fi
  next=$((current + 1))
  printf "$next" > "$TMPDIR/progress"
}

install_sudo_curl_git(){
  if ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v sudo >/dev/null 2>&1; then
    progress_echo "正在安装基础组件..."
    apt-get update || exit 1
    apt --fix-broken install -y || exit 1
    apt-get install -y sudo wget git curl || exit 1
  else
    progress_echo "基础组件已安装"
  fi


}

network_test() {
    local timeout=5
    local status=0
    local found=0
    target_proxy=""
    echo "开始网络测试: Github..."

    read_retry
    local count=$?
    if [ $count -ge $MAX_NETWORK_RETRY ]; then
      echo "网络测试已失败 $count 次（上限 $MAX_NETWORK_RETRY），暂停重试。请检查网络后重启应用。" > "$TMPDIR/progress_des"
      exit 1
    fi

    proxy_arr=("https://ghfast.top" "https://gh.wuliya.xin" "https://gh-proxy.com" "https://github.moeyy.xyz")
    check_url="https://raw.githubusercontent.com/NapNeko/NapCatQQ/main/package.json"

    for proxy in "${proxy_arr[@]}"; do
        echo "测试代理: ${proxy}"
        status=$(curl -k -L --connect-timeout ${timeout} --max-time $((timeout*2)) -o /dev/null -s -w "%{http_code}" "${proxy}/${check_url}")
        curl_exit=$?
        if [ $curl_exit -ne 0 ]; then
            echo "代理 ${proxy} 测试失败或超时，错误码: $curl_exit"
            continue
        fi
        if [ "${status}" = "200" ]; then
            found=1
            target_proxy="${proxy}"
            echo "将使用Github代理: ${proxy}"
            break
        fi
    done

    if [ ${found} -eq 0 ]; then
        echo "警告: 无法找到可用的Github代理，将尝试直连..."
        status=$(curl -k --connect-timeout ${timeout} --max-time $((timeout*2)) -o /dev/null -s -w "%{http_code}" "${check_url}")
        if [ $? -eq 0 ] && [ "${status}" = "200" ]; then
            echo "直连Github成功，将不使用代理"
            target_proxy=""
        else
            bump_retry
            echo "警告: 无法连接到Github，请检查网络。（尝试 $((count+1))/$MAX_NETWORK_RETRY）" > "$TMPDIR/progress_des"
            exit 1
        fi
    fi
    # 成功时重置计数
    rm -f "$NET_RETRY_FILE"
}

# 网络重试计数器
read_retry(){
  local c=0
  if [ -f "$NET_RETRY_FILE" ]; then
    c=$(cat "$NET_RETRY_FILE" 2>/dev/null | tr -cd '0-9')
  fi
  [ -z "$c" ] && c=0
  return $c
}
bump_retry(){
  local c=0
  if [ -f "$NET_RETRY_FILE" ]; then
    c=$(cat "$NET_RETRY_FILE" 2>/dev/null | tr -cd '0-9')
  fi
  [ -z "$c" ] && c=0
  echo $((c+1)) > "$NET_RETRY_FILE"
}

# 从 onebot11.json 同步 token/port 至 MaiBot 适配器 config.toml
sync_onebot_to_adapter_config(){
  local ONEBOT_PATH="$1"
  local ADAPTER_CFG="$2"
  if [ -f "$ONEBOT_PATH" ] && [ -f "$ADAPTER_CFG" ]; then
    local OB_TOKEN=""
    local OB_PORT=""
    if command -v python3 >/dev/null 2>&1; then
      OB_TOKEN=$(python3 -c "import json; d=json.load(open('$ONEBOT_PATH')); ws=d.get('network',{}).get('websocketServers',[{}])[0]; print(ws.get('token',''))" 2>/dev/null || true)
      OB_PORT=$(python3 -c "import json; d=json.load(open('$ONEBOT_PATH')); ws=d.get('network',{}).get('websocketServers',[{}])[0]; print(ws.get('port',8095))" 2>/dev/null || true)
    fi
    if [ -z "$OB_TOKEN" ]; then
      OB_TOKEN=$(grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' "$ONEBOT_PATH" 2>/dev/null | head -n 1 | cut -d'"' -f4 || true)
    fi
    if [ -z "$OB_PORT" ]; then
      OB_PORT=$(grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' "$ONEBOT_PATH" 2>/dev/null | head -n 1 | awk -F':' '{print $2}' | tr -d '[:space:]' || true)
    fi
    if [ -n "$OB_TOKEN" ]; then
      local ESCAPED_TOKEN=$(echo "$OB_TOKEN" | sed 's/[&\]/\\&/g')
      sed -i "s|^token = \".*\"|token = \"$ESCAPED_TOKEN\"|" "$ADAPTER_CFG"
      echo "✓ 已同步 onebot11.json token 到适配器 config.toml"
    fi
    if [ -n "$OB_PORT" ]; then
      sed -i "s|^port = [0-9]*|port = $OB_PORT|" "$ADAPTER_CFG"
      echo "✓ 已同步 onebot11.json port ($OB_PORT) 到适配器 config.toml"
    fi
  fi
}

install_uv(){
  INSTALL_DIR="$HOME/.local/bin"
  if [ ! -x "$INSTALL_DIR/uv" ]; then
    progress_echo "uv $L_NOT_INSTALLED，$L_INSTALLING..."
    network_test
    APP_NAME="uv"
    APP_VERSION="0.9.9"
    ARCHIVE_FILE="uv-aarch64-unknown-linux-gnu.tar.gz"
    DOWNLOAD_URL="${target_proxy:+${target_proxy}/}https://github.com/astral-sh/uv/releases/download/${APP_VERSION}/${ARCHIVE_FILE}"

    # 检查必要命令
    for cmd in tar mkdir cp chmod mktemp rm curl; do
      if ! command -v $cmd >/dev/null 2>&1; then
        echo "错误：缺少必要命令 $cmd，无法安装 $APP_NAME"
        exit 1
      fi
    done

    # 创建安装目录和临时目录
    mkdir -p $INSTALL_DIR
    TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -t 'uvtmp.XXXXXX')
    if [ -z "$TMP_DIR" ]; then
      echo "创建临时目录失败"
      exit 1
    fi
    mkdir -p "$TMP_DIR"
    TMP_ARCHIVE="$TMP_DIR/$ARCHIVE_FILE"

    # 下载并解压（失败直接退出，不使用return）
    echo "正在下载 $APP_NAME $APP_VERSION..."
    if ! curl -fL $DOWNLOAD_URL -o $TMP_ARCHIVE; then
      echo "下载失败"
      rm -rf $TMP_DIR
      exit 1
    fi
    echo "正在解压 $APP_NAME..."
    if ! tar -C "$TMP_DIR" -xf "$TMP_ARCHIVE" --strip-components 1; then
      echo "解压失败"
      rm -rf $TMP_DIR
      exit 1
    fi

    # 安装并授权
    cp $TMP_DIR/uv $TMP_DIR/uvx $INSTALL_DIR/
    chmod +x $INSTALL_DIR/uv $INSTALL_DIR/uvx

    # 自动配置 PATH（写入 Ubuntu root 的 bashrc）
    if ! grep -q "$INSTALL_DIR" $HOME/.bashrc; then
      echo "export PATH=$INSTALL_DIR:\$PATH" >> $HOME/.bashrc
      source $HOME/.bashrc
      echo "已自动配置 $APP_NAME 路径到环境变量"
    fi

    # 清理临时文件
    rm -rf $TMP_DIR
  else
    progress_echo "uv $L_INSTALLED"
  fi
}

# NapCat 真实安装判定：launcher.sh、QQ 主程序（非空且可执行）、napcat 运行目录（package.json）三者在位。
# 仅检查 launcher.sh 会在用户删除 ~/napcat 或 QQ 安装损坏时误判为已安装，跳过重装。
napcat_installed(){
  [ -f "$HOME/launcher.sh" ] && \
  [ -s "/opt/QQ/qq" ] && [ -x "/opt/QQ/qq" ] && \
  [ -f "$HOME/napcat/package.json" ]
}

install_napcat(){
  # 检查是否已安装（真实可用性判定）
  if ! napcat_installed; then
    progress_echo "Napcat $L_NOT_INSTALLED，$L_INSTALLING..."
    
    apt --fix-broken install -y

    # 备份配置目录（如果存在）
    if [ -d "$HOME/napcat/config" ]; then
      echo "备份 NapCat 配置目录..."
      cp -r "$HOME/napcat/config" "$HOME/napcat_config_backup"
    fi
    
    rm -rf $HOME/napcat
    cd $HOME
    echo "Napcat $L_NOT_INSTALLED，$L_INSTALLING..."
    network_test
    curl -o napcat.sh ${target_proxy:+${target_proxy}/}https://raw.githubusercontent.com/NapNeko/napcat-linux-installer/refs/heads/main/install.sh
    if ! chmod +x napcat.sh; then
      echo "设置 napcat.sh 执行权限失败"
      exit 1
    fi

    bash napcat.sh
    # 安装后校验：dpkg 状态必须为 install ok installed（dpkg -l 对 rc/iU 等残留状态同样返回 0），
    # 且安装判定三要素真实在位（QQ deb 下载损坏/apt 安装失败时安装器仍可能自报成功）
    if ! dpkg -s linuxqq 2>/dev/null | grep -q 'Status: install ok installed' || ! napcat_installed; then
      echo "NapCat 安装失败：QQ 未正确安装" > "$TMPDIR/progress_des"
      exit 1
    fi
    
    # 防止 napcat 安装器自动启动的进程与前台服务的独立 PTY 冲突
    echo "停止 NapCat 安装器自动启动的进程..."
    pkill -f "napcat" 2>/dev/null || true
    pkill -f "QQ" 2>/dev/null || true
    sleep 1
    
    # 恢复配置目录
    if [ -d "$HOME/napcat_config_backup" ]; then
      echo "恢复 NapCat 配置目录..."
      mkdir -p "$HOME/napcat/config"
      cp -r "$HOME/napcat_config_backup"/* "$HOME/napcat/config/"
      rm -rf "$HOME/napcat_config_backup"
    elif [ "$BACKUP_HAS_NAPCAT_CONFIG" -eq 1 ]; then
      echo "检测到备份，正在恢复备份的 NapCat 配置..."
      mkdir -p "$HOME/napcat/config"
      cp -r "$TMPDIR/backup_restore/napcat/config"/* "$HOME/napcat/config/"
    fi
    
  # 写入 onebot11.json 默认配置文件 (如果 onebot11.json 不存在才写入默认值)
  if [ ! -f "$HOME/napcat/config/onebot11.json" ]; then
    echo "写入 onebot11.json 默认配置文件"
    mkdir -p "$HOME/napcat/config"
    cat > "$HOME/napcat/config/onebot11.json" <<'EOF'
{
  "network": {
    "httpServers": [],
    "httpClients": [],
    "websocketServers": [
      {
        "name": "WsServer",
        "enable": true,
        "host": "127.0.0.1",
        "port": 8095,
        "reportSelfMessage": false,
        "enableForcePushEvent": true,
        "messagePostFormat": "array",
        "token": "kasdkfljsadhlskdjhasdlkfshdlafksjdhf",
        "debug": false,
        "heartInterval": 30000
      }
    ],
    "websocketClients": []
  },
  "musicSignUrl": "",
  "enableLocalFile2Url": false,
  "parseMultMsg": false
}
EOF
  fi
fi

  # 即使已经安装了 NapCat，如果 onebot11.json 缺失，也尝试从备份进行补齐（缺什么补什么）
  if [ ! -f "$HOME/napcat/config/onebot11.json" ]; then
    if [ "$BACKUP_HAS_NAPCAT_CONFIG" -eq 1 ]; then
      echo "检测到 NapCat 配置目录缺失且备份可用，正在从备份中补齐配置..."
      mkdir -p "$HOME/napcat/config"
      cp -r "$TMPDIR/backup_restore/napcat/config"/* "$HOME/napcat/config/"
    fi
  fi

  # 适配器 token/port 同步统一在 install_maibot 启动前执行一次，
  # 避免每次启动出现两条重复的同步日志
  progress_echo "Napcat $L_INSTALLED"
}

install_maibot(){
  local INSTALL_DIR="$HOME/MaiBot"
  local CLONE_TEMP_DIR="$HOME/MaiBot_tmp"

  rm -rf "$CLONE_TEMP_DIR"

  killall uv 2>/dev/null

  # [Fix 1.2] 全新安装时清除恢复标记
  if [ ! -d "$INSTALL_DIR" ]; then
    rm -f "$RESTORE_MARKER"
    cd $HOME
    progress_echo "MaiBot $L_NOT_INSTALLED，$L_INSTALLING..."

    # 克隆仓库（失败直接退出）
    echo "正在获取 MaiBot 最新版本..."

    # 判断是否使用自定义 git clone 命令
    if [ -n "$CUSTOM_GIT_CLONE" ]; then
      echo "使用自定义 Git Clone 命令..."
      echo "执行: $CUSTOM_GIT_CLONE"
      # 执行自定义命令，假设克隆到当前目录，然后重命名为临时目录
      if ! eval "$CUSTOM_GIT_CLONE"; then
        echo "自定义 Git Clone 命令执行失败"
        exit 1
      fi
      # 查找克隆后的目录（通常是 MaiBot）
      if [ -d "MaiBot" ]; then
        mv "MaiBot" "$CLONE_TEMP_DIR"
      else
        echo "错误: 自定义 git clone 后未找到 MaiBot 目录"
        exit 1
      fi
    else
      network_test
      
      # 强制使用 main 分支克隆 MaiBot
      CLONE_BRANCH="main"

      # 克隆到临时目录
      echo "正在克隆 MaiBot 仓库，分支: $CLONE_BRANCH..."
      if ! git clone --depth=1 --branch "$CLONE_BRANCH" ${target_proxy:+${target_proxy}/}https://github.com/Mai-with-u/MaiBot.git "$CLONE_TEMP_DIR"; then
        echo "克隆 MaiBot 仓库失败"
        rm -rf "$CLONE_TEMP_DIR"  # 清理失败的临时目录
        exit 1
      fi
    fi

    # 原子性重命名
    mv "$CLONE_TEMP_DIR" "$INSTALL_DIR" || exit 1

  else
    progress_echo "MaiBot $L_INSTALLED"
  fi

  # --- 插件恢复与默认适配器克隆 ---
  local ADAPTER_DIR="$INSTALL_DIR/plugins/MaiBot-Napcat-Adapter"
  
  # 避免覆盖用户现有的插件：只有当当前插件目录为空，或仅有官方初始文件时，才执行恢复
  local SHOULD_RESTORE=0
  if [ ! -d "$INSTALL_DIR/plugins" ]; then
    SHOULD_RESTORE=1
  else
    local OTHER_FILES=$(ls -A "$INSTALL_DIR/plugins" 2>/dev/null | grep -Ev "^(hello_world_plugin|__pycache__|__init__\.py)$" || true)
    if [ -z "$OTHER_FILES" ]; then
      SHOULD_RESTORE=1
    fi
  fi

  if [ "$BACKUP_HAS_MAIBOT_PLUGINS" -eq 1 ] && [ "$SHOULD_RESTORE" -eq 1 ]; then
    echo "检测到备份的自定义插件，正在从备份中恢复插件..."
    mkdir -p "$INSTALL_DIR/plugins"
    cp -r "$TMPDIR/backup_restore/MaiBot/plugins"/* "$INSTALL_DIR/plugins/"
    echo "插件恢复完成，跳过安装默认适配器"
  else
    # 如果没有备份插件，才进行默认适配器的下载
    if [ ! -d "$ADAPTER_DIR" ]; then
      progress_echo "安装默认适配器插件..."
      mkdir -p "$INSTALL_DIR/plugins"
      network_test
      if ! git clone --depth=1 --branch main ${target_proxy:+${target_proxy}/}https://github.com/MaiM-with-u/MaiBot-Napcat-Adapter.git "$ADAPTER_DIR"; then
        echo "适配器插件克隆失败"
        exit 1
      fi
      # 刚克隆下来删掉默认配置
      rm -f "$ADAPTER_DIR/config.toml"
    fi
    
    # [Fix] 插件目录存在但适配器配置缺失时，尝试从备份恢复（不覆盖已有配置）
    if [ "$BACKUP_HAS_MAIBOT_PLUGINS" -eq 1 ] && [ -d "$ADAPTER_DIR" ] && [ ! -f "$ADAPTER_DIR/config.toml" ]; then
      local BK_ADAPTER_CONFIG="$TMPDIR/backup_restore/MaiBot/plugins/MaiBot-Napcat-Adapter/config.toml"
      if [ -f "$BK_ADAPTER_CONFIG" ]; then
        echo "检测到适配器配置缺失且备份可用，正在从备份中恢复配置..."
        cp "$BK_ADAPTER_CONFIG" "$ADAPTER_DIR/config.toml"
      fi
    fi
  fi

  progress_echo "MaiBot 初始化中"
  cd "$INSTALL_DIR"

  # --- 数据恢复逻辑 (缺什么补什么合并) ---
  if [ ! -d "$INSTALL_DIR/data" ] || [ -z "$(ls -A "$INSTALL_DIR/data" 2>/dev/null)" ]; then
    echo "检测到 data 目录不存在或为空，准备从备份恢复..."
    mkdir -p "$INSTALL_DIR/data"
    
    if [ "$BACKUP_HAS_MAIBOT_DATA" -eq 1 ]; then
      echo "从备份中恢复 MaiBot 数据..."
      cp -r "$TMPDIR/backup_restore/MaiBot/data"/* "$INSTALL_DIR/data/"
      rm -rf "$INSTALL_DIR/.venv"
    fi
  fi

  # --- 额外的配置目录恢复逻辑 (缺什么补什么合并) ---
  if [ ! -d "$INSTALL_DIR/config" ] || [ -z "$(ls -A "$INSTALL_DIR/config" 2>/dev/null)" ]; then
    if [ -d "$TMPDIR/backup_restore/MaiBot/config" ] && [ -n "$(ls -A "$TMPDIR/backup_restore/MaiBot/config" 2>/dev/null)" ]; then
      echo "检测到 config 目录不存在或为空，从备份中恢复 MaiBot 配置..."
      mkdir -p "$INSTALL_DIR/config"
      cp -r "$TMPDIR/backup_restore/MaiBot/config"/* "$INSTALL_DIR/config/"
    fi
  fi
  
  if [ ! -d "$INSTALL_DIR/.venv" ]; then
    # 使用 uv sync 同步依赖
    echo "同步 MaiBot 依赖..."
    cd "$INSTALL_DIR"
    if ! $HOME/.local/bin/uv sync; then
      echo "依赖同步失败"
      exit 1
    fi
  fi

  # 确保 .venv 内部装有 pip 兼容层，供 MaiBot 自身的内置插件依赖管理器调用
  if [ -f "$HOME/.local/bin/uv" ]; then
    if ! "$INSTALL_DIR/.venv/bin/pip" --version >/dev/null 2>&1; then
      echo "虚拟环境未检测到 pip 兼容层，正在通过 uv 补齐安装..."
      cd "$INSTALL_DIR"
      $HOME/.local/bin/uv pip install pip
    fi
  fi

  # 启动 MaiBot（失败直接退出）
  cd "$INSTALL_DIR"
  if [ ! -f "$HOME/.local/bin/uv" ]; then
    echo "uv 未找到"
    exit 1
  fi

  # [Fix 1.2] 标记事务完成（所有恢复操作已完成）
  echo "done" > "$RESTORE_MARKER"

  # 启动 MaiBot Core (自动处理配置生成)
  # 拷贝适配器插件配置（目标不存在时才从预设拷贝，已有配置/备份恢复的不动）
  local TARGET_CONFIG="$INSTALL_DIR/plugins/MaiBot-Napcat-Adapter/config.toml"
  if [ -f "/root/config.toml" ] && [ ! -f "$TARGET_CONFIG" ]; then
      echo "正在拷贝适配器插件配置..."
      mkdir -p "$(dirname "$TARGET_CONFIG")"
      cp /root/config.toml "$TARGET_CONFIG"
  fi
  
  # [Fix 1.1] 从 onebot11.json 同步 token/port 覆盖到适配器 config.toml
  sync_onebot_to_adapter_config "$HOME/napcat/config/onebot11.json" "$TARGET_CONFIG"
  
  cd "$INSTALL_DIR"
  
  # [Fix 3.3] 动态计算 EULA 和 PRIVACY 的 MD5；文件不存在时自动同意
  if [ -f "EULA.md" ]; then
    export EULA_AGREE=$(md5sum EULA.md | awk '{print $1}')
  else
    export EULA_AGREE="agreed"
  fi

  if [ -f "PRIVACY.md" ]; then
    export PRIVACY_AGREE=$(md5sum PRIVACY.md | awk '{print $1}')
  else
    export PRIVACY_AGREE="agreed"
  fi
  
  echo "正在启动 MaiBot..."
  export PYTHONUNBUFFERED=1

  # [Fix 2.3] exec 前清理：apt 缓存、临时解压目录、网络重试计数器
  apt-get clean >/dev/null 2>&1 || true
  rm -rf "$TMPDIR/backup_restore"
  rm -f "$NET_RETRY_FILE"
  rm -f "$RESTORE_MARKER"
  
  # 陷阱函数不再需要清理这些（exec 替换了进程）
  trap '' EXIT
  
  exec $HOME/.local/bin/uv run bot.py
}

# 声明全局事务状态标记
BACKUP_HAS_NAPCAT_CONFIG=0
BACKUP_HAS_MAIBOT_DATA=0
BACKUP_HAS_MAIBOT_PLUGINS=0

# 备份预先解压与资产检验函数
stage_and_restore_backup(){
  # [Fix 1.2] 事务标记检查：若已完成则不重复执行
  if [ -f "$RESTORE_MARKER" ]; then
    echo "系统已标记为完整初始化，跳过备份恢复扫描"
    return
  fi
  local BACKUP_DIR="/sdcard/Download/MaiBot"
  local TEMP_RESTORE="$TMPDIR/backup_restore"
  
  rm -rf "$TEMP_RESTORE"
  
  # 检查当前系统是否缺少任何关键目录或文件（缺什么补什么）
  local NEED_RESTORE=0
  if [ ! -f "$HOME/napcat/config/onebot11.json" ]; then
    NEED_RESTORE=1
  fi
  if [ ! -d "$HOME/MaiBot/data" ] || [ -z "$(ls -A "$HOME/MaiBot/data" 2>/dev/null)" ]; then
    NEED_RESTORE=1
  fi
  if [ ! -d "$HOME/MaiBot/plugins" ] || [ -z "$(ls -A "$HOME/MaiBot/plugins" 2>/dev/null)" ]; then
    NEED_RESTORE=1
  fi
  if [ ! -d "$HOME/MaiBot/config" ] || [ -z "$(ls -A "$HOME/MaiBot/config" 2>/dev/null)" ]; then
    NEED_RESTORE=1
  fi

  if [ "$NEED_RESTORE" -eq 1 ]; then
    echo "检测到系统关键目录存在缺失，准备扫描并解析备份进行补全..."
    if [ -d "$BACKUP_DIR" ]; then
      LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/MaiBot-backup-*.tar.gz 2>/dev/null | head -n 1)
      if [ -n "$LATEST_BACKUP" ]; then
        echo "找到备份文件: $LATEST_BACKUP"
        echo "正在将备份解压至临时目录..."
        mkdir -p "$TEMP_RESTORE"
        
        if tar -xzf "$LATEST_BACKUP" -C "$TEMP_RESTORE"; then
          echo "备份解压完成，开始内容分析..."
          
          # 1. 检查 NapCat 配置文件
          if [ -d "$TEMP_RESTORE/napcat/config" ] && [ -n "$(ls -A "$TEMP_RESTORE/napcat/config" 2>/dev/null)" ]; then
            BACKUP_HAS_NAPCAT_CONFIG=1
            echo "✓ 备份检验：包含有效的 NapCat 配置文件"
          fi
          
          # 2. 检查 MaiBot 主运行数据
          if [ -d "$TEMP_RESTORE/MaiBot/data" ] && [ -n "$(ls -A "$TEMP_RESTORE/MaiBot/data" 2>/dev/null)" ]; then
            BACKUP_HAS_MAIBOT_DATA=1
            echo "✓ 备份检验：包含有效的 MaiBot 数据文件"
          fi
          
          # 3. 检查 plugins 目录
          if [ -d "$TEMP_RESTORE/MaiBot/plugins" ] && [ -n "$(find "$TEMP_RESTORE/MaiBot/plugins" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)" ]; then
            BACKUP_HAS_MAIBOT_PLUGINS=1
            echo "✓ 备份检验：包含自定义插件目录"
          fi
        else
          echo "警告：备份解压失败"
        fi
      else
        echo "未找到备份文件，将进行全新初始化"
      fi
    else
      echo "备份存放路径不存在，将进行全新初始化"
    fi
  else
    echo "系统运行环境完整，无需从备份恢复"
  fi
}

install_sudo_curl_git
bump_progress
install_uv
bump_progress
stage_and_restore_backup
install_napcat
bump_progress
install_maibot

