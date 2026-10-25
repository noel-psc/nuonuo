#!/usr/bin/env bash
# 在能稳定访问阿里云 ACR 的机器（国内笔记本 / ECS）上，把 GHCR 的镜像同步到 ACR。
#
# 为什么需要它：GitHub 托管 runner 到阿里云上海的公网链路在百 MB 级上传时会
# 被边缘节点重置（HTTP/2 PROTOCOL_ERROR），所以 ACR 同步不放在 CI 里做。
#
# 用法：
#   export ACR_REGISTRY=crpi-xxx.cn-shanghai.personal.cr.aliyuncs.com
#   export ACR_NAMESPACE=noel-dev
#   docker login ghcr.io -u <github用户名>            # 私有包需要 PAT(read:packages)
#   docker login "$ACR_REGISTRY" -u <阿里云账号>
#   ./deploy/sync-acr.sh                    # 默认同步 latest
#   ./deploy/sync-acr.sh latest sha-abc123  # 指定多个 tag
#
# 可选环境变量：
#   GHCR_IMAGE=ghcr.io/noel-psc/nuonuo   源镜像（默认按仓库名）
#   IMAGE_NAME=nuonuo                    ACR 里的仓库名（默认取源镜像名）
#   PLATFORM=linux/amd64                 要同步的架构（默认 amd64）
set -euo pipefail

: "${ACR_REGISTRY:?请先 export ACR_REGISTRY}"
: "${ACR_NAMESPACE:?请先 export ACR_NAMESPACE}"

GHCR_IMAGE="${GHCR_IMAGE:-ghcr.io/noel-psc/nuonuo}"
IMAGE_NAME="${IMAGE_NAME:-${GHCR_IMAGE##*/}}"
PLATFORM="${PLATFORM:-linux/amd64}"

if command -v docker >/dev/null 2>&1; then
  CLI=docker
elif command -v podman >/dev/null 2>&1; then
  CLI=podman
else
  echo "需要 docker 或 podman" >&2
  exit 1
fi

tags=("$@")
if [ "${#tags[@]}" -eq 0 ]; then
  tags=(latest)
fi

echo "使用 $CLI 同步 ${#tags[@]} 个 tag（${PLATFORM}）: ${GHCR_IMAGE} -> ${ACR_REGISTRY}/${ACR_NAMESPACE}/${IMAGE_NAME}"

for tag in "${tags[@]}"; do
  src="${GHCR_IMAGE}:${tag}"
  dst="${ACR_REGISTRY}/${ACR_NAMESPACE}/${IMAGE_NAME}:${tag}"
  echo "==> ${src} -> ${dst}"
  "$CLI" pull --platform "${PLATFORM}" "$src"
  "$CLI" tag "$src" "$dst"
  "$CLI" push "$dst"
done

echo "完成。服务器上把 .env 的 IMAGE 指向 ${ACR_REGISTRY}/${ACR_NAMESPACE}/${IMAGE_NAME}:latest 即可。"
