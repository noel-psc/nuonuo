"""诺诺 —— NoneBot2 入口（nb-cli 标准结构）。

`nb run` 会直接执行本文件；也可以 `uv run python bot.py`。
插件在 pyproject.toml 的 [tool.nonebot] 里声明，`src/plugins` 放本地插件。
"""

import nonebot
from nonebot.adapters.onebot.v11 import Adapter as OneBotV11Adapter
from nonebot.adapters.qq import Adapter as QQAdapter

nonebot.init()

driver = nonebot.get_driver()
driver.register_adapter(OneBotV11Adapter)
driver.register_adapter(QQAdapter)

# 容器健康检查用；非 ASGI 驱动没有 server_app 时跳过
server_app = getattr(driver, "server_app", None)
if server_app is not None:

    @server_app.get("/healthz")
    async def _healthz() -> dict[str, str]:
        return {"status": "ok"}


nonebot.load_from_toml("pyproject.toml")

if __name__ == "__main__":
    nonebot.run()
