import os
from pathlib import Path

import colorama

from aether_env.actions import Actions
from aether_env.config import ConfigError, load_settings
from aether_env.menu import MenuState, run_menu
from aether_env.preflight import missing_tools
from aether_env.runner import SubprocessRunner


def main(env: dict[str, str] | None = None) -> int:
    colorama.init()
    if env is None:
        env_file = Path(__file__).resolve().parents[1] / ".env"
        if env_file.exists():
            for line in env_file.read_text(encoding="utf-8").splitlines():
                stripped = line.strip()
                if not stripped or stripped.startswith("#") or "=" not in stripped:
                    continue
                key, value = stripped.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip())
    source = os.environ if env is None else env
    try:
        settings = load_settings(source)
    except ConfigError as exc:
        print("Missing keys in .env: " + ", ".join(exc.missing))
        return 2
    absent = missing_tools()
    if absent and env is None:
        print("Missing CLIs: " + ", ".join(absent))
        return 2
    if env is not None:
        return 0
    root = Path(__file__).resolve().parents[1]
    actions = Actions(settings, SubprocessRunner(), root, print)

    def on_run(state: MenuState) -> int:
        if state.action == "subir-ambiente":
            return actions.subir_ambiente(state.cluster_name or "")
        if state.action == "subir":
            return actions.subir_workload(state.cluster_name or "", state.workload_key or "")
        if state.action == "derrubar":
            return actions.derrubar_workload(state.cluster_name or "", state.workload_key or "")
        if state.action == "update":
            return actions.update_workload(state.cluster_name or "", state.workload_key or "")
        return 1

    def on_confirm(cluster: str, phrase: str) -> int:
        return actions.derrubar_ambiente(cluster, phrase)

    return run_menu(input, print, on_run, on_confirm)


if __name__ == "__main__":
    raise SystemExit(main())
