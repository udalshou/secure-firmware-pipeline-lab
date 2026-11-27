import importlib
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import lab_api


def test_ui_is_served_when_ui_dir_is_set(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    (tmp_path / "index.html").write_text("<h1>ui</h1>")
    monkeypatch.setenv("LAB_UI_DIR", str(tmp_path))
    client = TestClient(importlib.reload(lab_api).app)

    assert client.get("/").text == "<h1>ui</h1>"
    assert client.get("/health").json() == {"status": "ok"}


def test_ui_is_not_mounted_by_default(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("LAB_UI_DIR", raising=False)
    client = TestClient(importlib.reload(lab_api).app)

    assert client.get("/").status_code == 404
