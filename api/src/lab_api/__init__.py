"""Minimal appliance API: the payload the firmware pipeline builds and ships."""

import os
import time
from importlib.metadata import version

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

_STARTED = time.monotonic()

app = FastAPI(title="lab-api", version=version("lab-api"))


@app.get("/health")
def health() -> dict[str, str]:
    """Liveness probe for systemd and load balancers."""
    return {"status": "ok"}


@app.get("/status")
def status() -> dict[str, str | int]:
    """Device status shown by the web UI."""
    return {
        "version": version("lab-api"),
        "uptime_seconds": int(time.monotonic() - _STARTED),
    }


# On the device the API also serves the built web UI. Mounted last, so the API
# routes above take precedence over files of the same name.
_UI_DIR = os.environ.get("LAB_UI_DIR")
if _UI_DIR:
    app.mount("/", StaticFiles(directory=_UI_DIR, html=True), name="ui")


def main() -> None:
    """Entry point used by the systemd unit in the OS image."""
    import uvicorn

    uvicorn.run(
        app,
        host=os.environ.get("LAB_API_HOST", "127.0.0.1"),
        port=int(os.environ.get("LAB_API_PORT", "8080")),
    )
