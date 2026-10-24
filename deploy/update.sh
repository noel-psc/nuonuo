#!/usr/bin/env bash
# 服务器端更新脚本：拉取镜像并重建容器。
#
# 用法：
#   ./deploy/update.sh                 # 使用 .env 中的 IMAGE（一般是 :latest）
#   ./deploy/update.sh <镜像地址>       # 固定到某个 tag，例如回滚：
#                                      #   ./deploy/update.sh ghcr.io/owner/nuonuo:sha-<40位commit>
#   WITH_NAPCAT=1 ./deploy/update.sh   # 同时拉起 NapCat sidecar
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "错误：当前目录没有 .env，请先 cp .env.example .env 并填写 IMAGE 等配置" >&2
  exit 1
fi

image="${1:-}"
if [ -n "$image" ]; then
  export IMAGE="$image"
fi

profile_args=()
if [ "${WITH_NAPCAT:-0}" = "1" ]; then
  profile_args+=(--profile napcat)
fi

# 容器内 uid/gid：bot=10001，napcat=NAPCAT_UID/NAPCAT_GID（默认 1000）
# 挂载目录由 Docker 以 root 创建，属主不对会导致插件写 SQLite / secret.key 失败
ensure_owner() {
  local path="$1" owner="$2" uid
  uid="$(id -u)"
  mkdir -p "$path"
  if [ "$uid" = "0" ]; then
    chown -R "$owner" "$path"
  elif [ "$(stat -c %u "$path" 2>/dev/null || echo 0)" != "${owner%%:*}" ]; then
    echo "提示：$path 属主可能不匹配容器用户，请执行 sudo chown -R $owner $path" >&2
  fi
}

ensure_owner data 10001:10001
if [ "${WITH_NAPCAT:-0}" = "1" ]; then
  ensure_owner napcat/config "${NAPCAT_UID:-1000}:${NAPCAT_GID:-1000}"
  ensure_owner napcat/qq "${NAPCAT_UID:-1000}:${NAPCAT_GID:-1000}"
  ensure_owner napcat/plugins "${NAPCAT_UID:-1000}:${NAPCAT_GID:-1000}"
fi

echo "==> 拉取镜像"
docker compose ${profile_args[@]+"${profile_args[@]}"} pull bot

echo "==> 重建容器"
docker compose ${profile_args[@]+"${profile_args[@]}"} up -d --remove-orphans

echo "==> 当前状态"
docker compose ${profile_args[@]+"${profile_args[@]}"} ps

echo "==> 清理 7 天前未使用的旧镜像"
docker image prune -af --filter "until=168h" >/dev/null 2>&1 || true
