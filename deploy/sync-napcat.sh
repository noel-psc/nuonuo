#!/usr/bin/env bash
# 在能访问 Docker Hub 的机器（国内笔记本等）上，把 NapCat 镜像同步到阿里云 ACR。
#
# 为什么要中转：国内服务器直连 Docker Hub 往往超时；ACR 已验证可稳定访问。
#
# 用法：
#   export ACR_REGISTRY=crpi-xxx.cn-shanghai.personal.cr.aliyuncs.com
#   export ACR_NAMESPACE=noel-dev
#   podman login "$ACR_REGISTRY" -u <阿里云账号>
#
#   ./deploy/sync-napcat.sh                 # 同步 latest
#   ./deploy/sync-napcat.sh v4.18.41        # 同步指定版本（推荐，可回滚）
#   NAPCAT_SOURCE=mlikiowa/napcat-docker ./deploy/sync-napcat.sh v4.18.41
set -euo pipefail

: "${ACR_REGISTRY:?请先 export ACR_REGISTRY}"
: "${ACR_NAMESPACE:?请先 export ACR_NAMESPACE}"

SOURCE="${NAPCAT_SOURCE:-mlikiowa/napcat-docker}"
PLATFORM="${PLATFORM:-linux/amd64}"
tag="${1:-latest}"
dst_repo="${ACR_REGISTRY}/${ACR_NAMESPACE}/napcat-docker"

if command -v docker >/dev/null 2>&1; then
  CLI=docker
elif command -v podman >/dev/null 2>&1; then
  CLI=podman
else
  echo "需要 docker 或 podman" >&2
  exit 1
fi

echo "==> 拉取 ${SOURCE}:${tag}（${PLATFORM}）"
"$CLI" pull --platform "$PLATFORM" "${SOURCE}:${tag}"

echo "==> 推送 ${dst_repo}:${tag}"
"$CLI" tag "${SOURCE}:${tag}" "${dst_repo}:${tag}"
"$CLI" push "${dst_repo}:${tag}"

if [ "$tag" != "latest" ]; then
  echo "==> 同时更新 ${dst_repo}:latest"
  "$CLI" tag "${SOURCE}:${tag}" "${dst_repo}:latest"
  "$CLI" push "${dst_repo}:latest"
fi

cat <<EOF

同步完成。服务器上执行：

  cd /opt/nuonuo
  # 固定版本时，先把 .env 里的 NAPCAT_IMAGE 改成：
  #   ${dst_repo}:${tag}
  sudo docker compose pull napcat
  sudo docker compose --profile napcat up -d
EOF
