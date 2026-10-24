# syntax=docker/dockerfile:1
#
# 诺诺 运行镜像：多阶段 + uv，最终镜像只含 venv 与 bot.py。
# 支持 linux/amd64 与 linux/arm64（ddddocr/onnxruntime 均有对应 wheel）。
#
# ⚠️ 两个阶段必须同为 Debian bookworm（python:3.12-slim-bookworm 系），
#    否则 builder 里生成的 venv 在运行阶段不可移植（解释器路径/ld-linux 不一致）。
#

ARG PYTHON_VERSION=3.12

# ────────────────────────────── 构建阶段 ──────────────────────────────
FROM ghcr.io/astral-sh/uv:python${PYTHON_VERSION}-bookworm-slim AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /app

# 先只拷依赖清单，命中缓存时无需重装全部依赖
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project

# ────────────────────────────── 运行阶段 ──────────────────────────────
FROM python:${PYTHON_VERSION}-slim-bookworm AS runtime

# HOST=0.0.0.0：容器内必须监听全网卡，否则 NapCat 连不上而健康检查仍是绿的
# LOCALSTORE_DATA_DIR：插件数据落到 /app/data，与 compose 的挂载卷一致
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/app/.venv/bin:${PATH}" \
    HOST=0.0.0.0 \
    LOCALSTORE_DATA_DIR=/app/data \
    TZ=Asia/Shanghai

# libgomp1: onnxruntime 运行时依赖；tzdata: 插件使用 ZoneInfo("Asia/Shanghai")
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        libgomp1 \
        tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 10001 nuonuo \
    && useradd --uid 10001 --gid nuonuo --no-create-home \
        --home-dir /app --shell /usr/sbin/nologin nuonuo \
    && mkdir -p /app/data \
    && chown -R nuonuo:nuonuo /app

WORKDIR /app

COPY --from=builder --chown=nuonuo:nuonuo /app/.venv /app/.venv
COPY --chown=nuonuo:nuonuo bot.py pyproject.toml ./

USER nuonuo

EXPOSE 8080

# PORT 为空串时回退 8080（os.getenv 的默认值只在未设置时生效）
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + (os.getenv('PORT') or '8080') + '/healthz', timeout=3)"

CMD ["python", "bot.py"]
