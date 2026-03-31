#!/usr/bin/env python3
from __future__ import annotations

import importlib
import json
import os
import sys
import time
import traceback
from pathlib import Path
from typing import Any

try:
    import unreal  # type: ignore
except Exception:  # pragma: no cover - imported by Unreal, not CPython
    unreal = None


HEARTBEAT_INTERVAL_SEC = 0.5
_ACTIVE_BRIDGE = None


def _project_dir() -> Path:
    if unreal is None:
        raise RuntimeError("Unreal Python module is unavailable")
    return Path(str(unreal.Paths.project_dir())).resolve()


def _project_name() -> str:
    if unreal is None:
        return ""
    return str(unreal.Paths.get_base_filename(unreal.Paths.get_project_file_path()))


def _ensure_scripts_on_path(project_dir: Path) -> Path:
    scripts_dir = project_dir / "scripts"
    token = str(scripts_dir)
    if token not in sys.path:
        sys.path.insert(0, token)
    return scripts_dir


class UnrealEditorBridge:
    def __init__(self) -> None:
        if unreal is None:
            raise RuntimeError("Unreal Python module is unavailable")

        self.project_dir = _project_dir()
        _ensure_scripts_on_path(self.project_dir)

        import qq_engine  # type: ignore
        import unreal_editor_command  # type: ignore

        self.qq_engine = importlib.reload(qq_engine)
        self.command_module = importlib.reload(unreal_editor_command)
        self.metadata = self.qq_engine.engine_metadata("unreal")
        self.state_path = self.project_dir / str(self.metadata.get("editorBridgeStateFile") or ".qq/state/qq-unreal-editor-bridge.json")
        self.request_dir = self.project_dir / str(self.metadata.get("editorBridgeRequestDir") or ".qq/state/qq-unreal-editor/requests")
        self.response_dir = self.project_dir / str(self.metadata.get("editorBridgeResponseDir") or ".qq/state/qq-unreal-editor/responses")
        self.console_path = self.project_dir / str(self.metadata.get("editorBridgeConsoleFile") or ".qq/state/qq-unreal-editor-console.jsonl")
        self.log_path = self.project_dir / str(self.metadata.get("editorBridgeLogFile") or ".qq/state/qq-unreal-editor.log")
        self.tick_handle = None
        self.shutdown_handle = None
        self.last_heartbeat_unix = 0.0

    def ensure_dirs(self) -> None:
        self.request_dir.mkdir(parents=True, exist_ok=True)
        self.response_dir.mkdir(parents=True, exist_ok=True)
        self.console_path.parent.mkdir(parents=True, exist_ok=True)
        self.log_path.parent.mkdir(parents=True, exist_ok=True)

    def write_json(self, path: Path, payload: dict[str, Any]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        temp_path = path.with_suffix(f"{path.suffix}.tmp")
        temp_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        temp_path.replace(path)

    def append_console(self, level: str, event: str, payload: dict[str, Any]) -> None:
        self.ensure_dirs()
        entry = {
            "level": level,
            "event": event,
            "timestampUnix": time.time(),
            "payload": payload,
        }
        with self.console_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
        try:
            with self.log_path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
        except OSError:
            pass

    def write_state(self, *, extra: dict[str, Any] | None = None) -> None:
        payload = {
            "ok": True,
            "running": True,
            "engine": "unreal",
            "engineVersion": str(unreal.SystemLibrary.get_engine_version()),
            "projectDir": str(self.project_dir),
            "projectName": _project_name(),
            "pid": os.getpid(),
            "requestDir": str(self.request_dir),
            "responseDir": str(self.response_dir),
            "consoleFile": str(self.console_path),
            "lastHeartbeatUnix": time.time(),
        }
        if extra:
            payload.update(extra)
        self.write_json(self.state_path, payload)
        self.last_heartbeat_unix = float(payload["lastHeartbeatUnix"])

    def process_request(self, request_path: Path) -> None:
        request_id = request_path.stem
        try:
            payload = json.loads(request_path.read_text(encoding="utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("Request payload must be an object")
            request_id = str(payload.get("requestId") or request_path.stem)
            command = str(payload.get("command") or "").strip()
            args = payload.get("args") or {}
            if not isinstance(args, dict):
                raise ValueError("Request args must be an object")
            response = self.command_module.dispatch(command, args)
            if not isinstance(response, dict):
                response = {"ok": False, "category": "INVALID_RESPONSE", "message": "Unreal command helper returned a non-object response"}
            response.setdefault("command", command)
            response.setdefault("requestId", request_id)
            self.write_json(self.response_dir / f"{request_id}.json", response)
            self.append_console("info" if bool(response.get("ok")) else "error", command or "unknown", {"requestId": request_id, "response": response})
        except Exception as exc:
            response = {
                "ok": False,
                "category": "UNHANDLED_EXCEPTION",
                "message": str(exc),
                "requestId": request_id,
                "details": {"traceback": traceback.format_exc()},
            }
            self.write_json(self.response_dir / f"{request_id}.json", response)
            self.append_console("error", "request-failed", {"requestId": request_id, "response": response})
        finally:
            request_path.unlink(missing_ok=True)

    def tick(self, delta_seconds: float) -> None:
        _ = delta_seconds
        now = time.time()
        if (now - self.last_heartbeat_unix) >= HEARTBEAT_INTERVAL_SEC:
            self.write_state()
        for request_path in sorted(self.request_dir.glob("*.json")):
            self.process_request(request_path)

    def shutdown(self) -> None:
        payload = {
            "ok": True,
            "running": False,
            "engine": "unreal",
            "projectDir": str(self.project_dir),
            "projectName": _project_name(),
            "pid": os.getpid(),
            "lastHeartbeatUnix": time.time(),
        }
        try:
            self.write_json(self.state_path, payload)
        except Exception:
            pass
        self.append_console("info", "bridge-stopped", {"projectDir": str(self.project_dir)})
        if self.tick_handle is not None:
            try:
                unreal.unregister_slate_post_tick_callback(self.tick_handle)
            except Exception:
                pass
            self.tick_handle = None
        if self.shutdown_handle is not None:
            try:
                unreal.unregister_python_shutdown_callback(self.shutdown_handle)
            except Exception:
                pass
            self.shutdown_handle = None

    def start(self) -> None:
        self.ensure_dirs()
        self.write_state()
        self.tick_handle = unreal.register_slate_post_tick_callback(self.tick)
        try:
            self.shutdown_handle = unreal.register_python_shutdown_callback(self.shutdown)
        except Exception:
            self.shutdown_handle = None
        self.append_console(
            "info",
            "bridge-started",
            {
                "projectDir": str(self.project_dir),
                "projectName": _project_name(),
                "pid": os.getpid(),
            },
        )


def start() -> None:
    global _ACTIVE_BRIDGE
    if _ACTIVE_BRIDGE is not None:
        return
    _ACTIVE_BRIDGE = UnrealEditorBridge()
    _ACTIVE_BRIDGE.start()

