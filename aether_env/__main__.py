import os
from pathlib import Path

import colorama

from aether_env.actions import Actions
from aether_env.config import ConfigError, SecretConfigError, load_settings, read_dotenv
from aether_env.menu import MenuState, run_menu
from aether_env.preflight import missing_tools
from aether_env.runner import SubprocessRunner


def main(env: dict[str, str] | None = None) -> int:
    colorama.init()
    env_file = Path(__file__).resolve().parents[1] / ".env"
    dotenv = read_dotenv(env_file) if env is None else dict(env)
    if env is None:
        for key, value in dotenv.items():
            os.environ.setdefault(key, value)
    source = os.environ if env is None else env
    try:
        settings = load_settings(source, app_env=dotenv)
    except ConfigError as exc:
        print("Missing keys in .env: " + ", ".join(exc.missing))
        return 2
    except SecretConfigError as exc:
        print(str(exc))
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
        if state.action == "escalar-ambiente-zero":
            return actions.escalar_ambiente_zero(state.cluster_name or "")
        if state.action == "subir":
            return actions.subir_workload(state.cluster_name or "", state.workload_key or "")
        if state.action == "escalar-zero":
            return actions.escalar_workload_zero(state.cluster_name or "", state.workload_key or "")
        if state.action == "update":
            return actions.update_workload(state.cluster_name or "", state.workload_key or "")
        return 1

    return run_menu(input, print, on_run)


if __name__ == "__main__":
    raise SystemExit(main())
