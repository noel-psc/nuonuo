"""诺诺 —— NoneBot2 宿主入口。

职责很薄：初始化 NoneBot、按环境变量注册适配器、挂一个健康检查端点，
然后把插件交由 pyproject.toml 的 [tool.nonebot] 声明式加载。
"""

from __future__ import annotations

import os

from dotenv import dotenv_values

# NoneBot 只把 .env 读进自己的 Config，不会注入 os.environ；
# 适配器开关需要自己读一遍，容器里由 compose env_file 注入的环境变量优先级更高。
ENV_FILE = os.getenv("NUONUO_ENV_FILE", ".env")


def _load_env() -> dict[str, str]:
    values: dict[str, str] = {}
    if os.path.isfile(ENV_FILE):
        values.update(
            {k: v for k, v in dotenv_values(ENV_FILE).items() if v is not None}
        )
    values.update(os.environ)
    return values


_ENV = _load_env()


def _flag(name: str, default: str = "false") -> bool:
    """读取布尔型环境变量，兼容 1/true/yes/on。"""
    return str(_ENV.get(name, default)).strip().lower() in {"1", "true", "yes", "on"}


import nonebot  # noqa: E402

nonebot.init()

driver = nonebot.get_driver()

_enabled_adapters: list[str] = []

if _flag("ENABLE_ONEBOT_V11", "true"):
    from nonebot.adapters.onebot.v11 import Adapter as OneBotV11Adapter

    driver.register_adapter(OneBotV11Adapter)
    _enabled_adapters.append("OneBot V11")

if _flag("ENABLE_QQ_OFFICIAL", "false"):
    from nonebot.adapters.qq import Adapter as QQAdapter

    driver.register_adapter(QQAdapter)
    _enabled_adapters.append("QQ 官方")

if not _enabled_adapters:
    raise SystemExit(
        "未启用任何适配器：请设置 ENABLE_ONEBOT_V11=true 或 ENABLE_QQ_OFFICIAL=true"
    )

# 健康检查端点（仅 ASGI 驱动，如 fastapi 提供 server_app）
server_app = getattr(driver, "server_app", None)
if server_app is not None:

    @server_app.get("/healthz")
    async def _healthz() -> dict[str, str]:
        return {"status": "ok"}


nonebot.logger.info(f"诺诺启动，已启用适配器：{'、'.join(_enabled_adapters)}")

# 从 pyproject.toml 的 [tool.nonebot] 加载插件（当前为 nonebot_plugin_sues_bill）
nonebot.load_from_toml("pyproject.toml")

nonebot.run()
