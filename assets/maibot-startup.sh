#!/bin/bash

MAIBOT_APP_VERSION="{{VERSION}}"
export UV_LINK_MODE=copy

# 自定义 Git Clone 命令（为空时使用默认逻辑）
CUSTOM_GIT_CLONE=""

# 重装插件依赖标记（1表示需要重装，执行后自动清除）
REINSTALL_PLUGINS_FLAG=0

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
    apt-get update
    apt --fix-broken install -y
    apt-get install -y sudo wget git curl
  else
    progress_echo "基础组件已安装"
  fi


}

network_test() {
    local timeout=10
    local status=0
    local found=0
    target_proxy=""
    echo "开始网络测试: Github..."

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
            echo "警告: 无法连接到Github，请检查网络。将继续尝试安装，但可能会失败。"
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

install_napcat(){
  # 检查是否已安装
  if [ ! -f "$HOME/launcher.sh" ]; then
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
    
  # 写入 onebot11.json 默认配置文件 (如果 napcat/config 目录为空或不存在才写入默认值)
  if [ ! -d "$HOME/napcat/config" ] || [ -z "$(ls -A "$HOME/napcat/config" 2>/dev/null)" ]; then
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
  progress_echo "Napcat $L_INSTALLED"
}

install_maibot(){
  local INSTALL_DIR="$HOME/MaiBot"
  local CLONE_TEMP_DIR="$HOME/MaiBot_tmp"

  rm -rf "$CLONE_TEMP_DIR"

  killall uv 2>/dev/null

  # 检查是否已安装
  if [ ! -d "$INSTALL_DIR" ]; then
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
    mv "$CLONE_TEMP_DIR" "$INSTALL_DIR"

  else
    progress_echo "MaiBot $L_INSTALLED"
  fi

  # --- 插件安装逻辑 (事务和备份合并) ---
  local ADAPTER_DIR="$INSTALL_DIR/plugins/MaiBot-Napcat-Adapter"
  
  # 判断：如果备份中含有自定义插件，我们将这些插件覆盖复制进去，并且不安装默认适配器
  if [ "$BACKUP_HAS_MAIBOT_PLUGINS" -eq 1 ]; then
    echo "检测到备份中包含插件，正在恢复备份的插件目录..."
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
  fi

  progress_echo "MaiBot 初始化中"
  cd "$INSTALL_DIR"

  # --- 数据恢复逻辑 ---
  if [ ! -d "$INSTALL_DIR/data" ]; then
    echo "检测到 data 目录不存在，初始化数据目录..."
    mkdir -p "$INSTALL_DIR/data"
    
    if [ "$BACKUP_HAS_MAIBOT_DATA" -eq 1 ]; then
      echo "从备份中恢复 MaiBot 数据..."
      cp -r "$TMPDIR/backup_restore/MaiBot/data"/* "$INSTALL_DIR/data/"
      REINSTALL_PLUGINS_FLAG=1  # 恢复成功，标记需要重装插件依赖
    fi
    
    rm -rf "$INSTALL_DIR/.venv"
  fi

  # --- 额外的配置目录恢复逻辑 ---
  if [ -d "$TMPDIR/backup_restore/MaiBot/config" ] && [ -n "$(ls -A "$TMPDIR/backup_restore/MaiBot/config" 2>/dev/null)" ]; then
    echo "从备份中恢复 MaiBot 配置目录..."
    mkdir -p "$INSTALL_DIR/config"
    cp -r "$TMPDIR/backup_restore/MaiBot/config"/* "$INSTALL_DIR/config/"
  fi

  if [ ! -d "$INSTALL_DIR/.venv" ]; then

    # 使用 uv sync 同步依赖
    echo "同步 MaiBot 依赖..."
    cd "$INSTALL_DIR"
    if ! $HOME/.local/bin/uv sync; then
      echo "依赖同步失败"
      exit 1
    fi

    REINSTALL_PLUGINS_FLAG=1  # .venv 不存在，需要重装插件依赖
  fi

  # 检查是否需要重装插件依赖（根据标记）
  if [ "$REINSTALL_PLUGINS_FLAG" -eq 1 ]; then

    echo "检测到重装插件依赖标记，开始重装..."
    # 清除标记（将脚本中的标记重置为0）
    sed -i 's/^REINSTALL_PLUGINS_FLAG=1$/REINSTALL_PLUGINS_FLAG=0/' /root/maibot-startup.sh

    # 扫描所有插件的 requirements.txt 并安装到 venv
    echo "扫描插件依赖..."
    if [ -d "$INSTALL_DIR/plugins" ]; then
      for plugin_dir in "$INSTALL_DIR/plugins"/*; do
        if [ -d "$plugin_dir" ] && [ -f "$plugin_dir/requirements.txt" ]; then
          echo "发现插件依赖: $plugin_dir/requirements.txt"
          if [ -f "$HOME/.local/bin/uv" ]; then
            cd "$INSTALL_DIR"
            echo "安装插件依赖: $(basename "$plugin_dir")..."
            $HOME/.local/bin/uv pip install -r "$plugin_dir/requirements.txt" 2>/dev/null || echo "警告: 插件依赖安装失败，将在启动时重试"
          fi
        fi
      done
    fi
  fi

  # 启动 MaiBot（失败直接退出）
  cd "$INSTALL_DIR"
  if [ ! -f "$HOME/.local/bin/uv" ]; then
    echo "uv 未找到"
    exit 1
  fi

  # 启动 MaiBot Core (自动处理配置生成)
  progress_echo "MaiBot Core 配置中"
  
  # 拷贝适配器插件配置 (仅在未使用备份插件，且目标配置不存在时复制)
  local TARGET_CONFIG="$INSTALL_DIR/plugins/MaiBot-Napcat-Adapter/config.toml"
  if [ "$BACKUP_HAS_MAIBOT_PLUGINS" -eq 0 ]; then
    if [ -f "/root/config.toml" ] && [ ! -f "$TARGET_CONFIG" ]; then
      echo "正在拷贝适配器插件配置..."
      mkdir -p "$(dirname "$TARGET_CONFIG")"
      cp /root/config.toml "$TARGET_CONFIG"
    fi
  else
    echo "检测到备份插件，跳过默认适配器配置拷贝"
  fi

  cd "$INSTALL_DIR"
  
  # 动态计算 EULA 和 PRIVACY 的 MD5
  if [ -f "EULA.md" ]; then
    export EULA_AGREE=$(md5sum EULA.md | awk '{print $1}')
  else
    export EULA_AGREE="1b662741904d7155d1ce1c00b3530d0d"
  fi

  if [ -f "PRIVACY.md" ]; then
    export PRIVACY_AGREE=$(md5sum PRIVACY.md | awk '{print $1}')
  else
    export PRIVACY_AGREE="9943b855e72199d0f5016ea39052f1b6"
  fi
  
  echo "正在启动 MaiBot..."
  export PYTHONUNBUFFERED=1
  exec $HOME/.local/bin/uv run bot.py
}

# 声明全局事务状态标记
BACKUP_HAS_NAPCAT_CONFIG=0
BACKUP_HAS_MAIBOT_DATA=0
BACKUP_HAS_MAIBOT_PLUGINS=0

# 备份预先解压与资产检验函数
stage_and_restore_backup(){
  local BACKUP_DIR="/sdcard/Download/MaiBot"
  local TEMP_RESTORE="$TMPDIR/backup_restore"
  local DATA_DIR="$HOME/MaiBot/data"
  
  rm -rf "$TEMP_RESTORE"
  
  # 如果目前还没有主数据目录，则表明是全新初始化/清除数据，尝试从备份恢复
  if [ ! -d "$DATA_DIR" ]; then
    echo "检测到 data 目录不存在，准备扫描并解析备份..."
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
          # 通过查找子文件夹（不限制是否为空），判断用户在备份中是否定制了插件（包含默认测试插件等）
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

# 整体安装完后，清理备份临时解压目录
rm -rf "$TMPDIR/backup_restore"
