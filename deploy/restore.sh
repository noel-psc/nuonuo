#!/usr/bin/env bash
# 从旧部署的备份恢复插件数据到当前部署的 ./data 卷。
#
# 用法：
#   ./deploy/restore.sh /path/to/backup      # 备份根目录（其下有 data/nonebot_plugin_sues_bill/）
#   ./deploy/restore.sh /path/to/data        # 或直接指向 data 目录
#   ./deploy/restore.sh /path/to/nonebot_plugin_sues_bill
#   WITH_NAPCAT=1 ./deploy/restore.sh ...    # 同时管理 NapCat sidecar
#
# 做的事：停服 → 现存数据留一份 data.bak.<时间> → 拷入备份 → 修正属主 → 起服 → 校验。
set -euo pipefail
cd "$(dirname "$0")/.."

src="${1:-}"
if [ -z "$src" ]; then
  echo "用法: $0 <旧数据目录>" >&2
  echo "  例: $0 /opt/nuonuo/backup/data" >&2
  exit 1
fi
[ -d "$src" ] || { echo "目录不存在: $src" >&2; exit 1; }
[ -f .env ] || { echo "当前目录没有 .env，请先 cp .env.example .env" >&2; exit 1; }

# 兼容三种传入方式
if [ -f "$src/sues_bill.sqlite3" ]; then
  plugin_data="$src"
elif [ -f "$src/nonebot_plugin_sues_bill/sues_bill.sqlite3" ]; then
  plugin_data="$src/nonebot_plugin_sues_bill"
elif [ -f "$src/data/nonebot_plugin_sues_bill/sues_bill.sqlite3" ]; then
  plugin_data="$src/data/nonebot_plugin_sues_bill"
else
  echo "在 $src 下找不到 nonebot_plugin_sues_bill/sues_bill.sqlite3" >&2
  exit 1
fi

if [ ! -f "$plugin_data/secret.key" ]; then
  echo "警告：$plugin_data 里没有 secret.key，已加密的校园卡密码将无法解密！" >&2
fi

profile_args=()
if [ "${WITH_NAPCAT:-0}" = "1" ]; then
  profile_args+=(--profile napcat)
fi
compose=(docker compose ${profile_args[@]+"${profile_args[@]}"})

echo "==> 停止机器人"
"${compose[@]}" stop bot >/dev/null 2>&1 || true

if [ -d data/nonebot_plugin_sues_bill ]; then
  backup="data.bak.$(date +%Y%m%d-%H%M%S)"
  echo "==> 现存数据备份到 $backup"
  cp -a data "$backup"
fi

echo "==> 复制 $plugin_data -> data/nonebot_plugin_sues_bill"
mkdir -p data/nonebot_plugin_sues_bill
cp -a "$plugin_data/." data/nonebot_plugin_sues_bill/

# 容器内 bot 以 uid 10001 运行
if [ "$(id -u)" = "0" ]; then
  chown -R 10001:10001 data
else
  echo "提示：非 root，请手动执行 sudo chown -R 10001:10001 data"
fi

echo "==> 启动机器人"
"${compose[@]}" up -d

echo "==> 等待健康检查"
for _ in $(seq 1 30); do
  if "${compose[@]}" ps --format '{{.Health}}' bot 2>/dev/null | grep -q healthy; then
    echo "机器人已 healthy"
    break
  fi
  sleep 2
done

echo "==> 最近日志"
"${compose[@]}" logs --tail=20 bot
echo
echo "恢复完成。请在 QQ 里发 #电费 或 #耗电历史 验证数据。"
