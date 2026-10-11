from collections.abc import Callable
from dataclasses import dataclass

from aether_env.catalog import WORKLOADS
from aether_env.theme import PROD, QA, Theme, theme_for

_FRAME_WIDTH = 50
_INNER_WIDTH = _FRAME_WIDTH - 2


@dataclass(frozen=True)
class MenuState:
    screen: str
    cluster_name: str | None = None
    workload_key: str | None = None
    action: str | None = None
    replicas: int | None = None


def next_state(state: MenuState, choice: str) -> MenuState | None:
    choice = choice.strip()
    if state.screen == "root":
        if choice == "1":
            return MenuState("environment", QA.cluster_name)
        if choice == "2":
            return MenuState("environment", PROD.cluster_name)
        if choice == "0":
            return None
        return state
    if state.screen == "environment":
        if choice == "1":
            return MenuState("run", state.cluster_name, action="subir-ambiente")
        if choice == "2":
            return MenuState("scale_prompt", state.cluster_name)
        if choice == "3":
            return MenuState("workloads", state.cluster_name)
        if choice == "4":
            return MenuState("run", state.cluster_name, action="status")
        if choice == "0":
            return MenuState("root")
        return state
    if state.screen == "workloads":
        if choice == "0":
            return MenuState("environment", state.cluster_name)
        if choice.isdigit() and 1 <= int(choice) <= len(WORKLOADS):
            workload = WORKLOADS[int(choice) - 1]
            return MenuState("action", state.cluster_name, workload.key)
        return state
    if state.screen == "action":
        if choice == "1":
            return MenuState("run", state.cluster_name, state.workload_key, "subir")
        if choice == "2":
            return MenuState("scale_prompt", state.cluster_name, state.workload_key)
        if choice == "3":
            return MenuState("run", state.cluster_name, state.workload_key, "update")
        if choice == "4":
            return MenuState("run", state.cluster_name, state.workload_key, "logs")
        if choice == "0":
            return MenuState("workloads", state.cluster_name)
        return state
    return state


def _pad_visible(text: str, width: int) -> str:
    visible = 0
    index = 0
    while index < len(text):
        if text[index] == "\033":
            end = text.find("m", index)
            if end == -1:
                break
            index = end + 1
            continue
        visible += 1
        index += 1
    if visible >= width:
        return text
    return text + (" " * (width - visible))


def _frame(theme: Theme, title: str, body_lines: list[str]) -> str:
    rule = "─" * _INNER_WIDTH
    top = f"{theme.accent}╭{rule}╮{theme.reset}"
    bottom = f"{theme.accent}╰{rule}╯{theme.reset}"

    def frame_line(content: str) -> str:
        padded = _pad_visible(content, _INNER_WIDTH)
        return f"{theme.accent}│{theme.reset}{padded}{theme.accent}│{theme.reset}"

    title_line = frame_line(f" {title} ")
    content_lines = [frame_line(line) for line in body_lines]
    return "\n".join([top, title_line, *content_lines, bottom])


def _line(content: str) -> str:
    return _pad_visible(content, _INNER_WIDTH)


def _blank(_theme: Theme) -> str:
    return _line("")


def _option(theme: Theme, number: str, label: str) -> str:
    content = f"  {theme.accent}{number}{theme.reset}  {theme.text}{label}{theme.reset}"
    return _line(content)


def _section(theme: Theme, label: str) -> str:
    content = f"  {theme.dim}{label}{theme.reset}"
    return _line(content)


def _back_line(theme: Theme) -> str:
    return _option(theme, "0", "Back")


def _root_option(number: str, label: str, accent: str, text: str, reset: str) -> str:
    content = f"  {accent}{number}{reset}  {accent}{label}{reset}"
    return _line(content)


def render(state: MenuState) -> str:
    if state.screen == "root":
        body = [
            _blank(QA),
            _root_option("1", "QA", QA.accent, QA.text, QA.reset),
            _root_option("2", "Production", PROD.accent, PROD.text, PROD.reset),
            _blank(QA),
            _root_option("0", "Exit", QA.text, QA.text, QA.reset),
        ]
        return "\n".join([_frame(QA, "Aether", body), ""])

    theme = theme_for(state.cluster_name or "")
    if state.screen == "environment":
        body = [
            _blank(theme),
            _option(theme, "1", "Start environment"),
            _option(theme, "2", "Scale to"),
            _option(theme, "3", "Choose workload"),
            _option(theme, "4", "Container status"),
            _blank(theme),
            _back_line(theme),
        ]
        return "\n".join([_frame(theme, theme.cluster_name, body), ""])
    if state.screen == "scale_prompt":
        target = "all workloads" if not state.workload_key else state.workload_key
        body = [
            _blank(theme),
            _line(f"  {theme.text}Replica count for {target}:{theme.reset}"),
            _line(f"  {theme.dim}Enter a number (0 stops pods).{theme.reset}"),
            _blank(theme),
        ]
        return "\n".join([_frame(theme, "Scale to", body), ""])
    if state.screen == "workloads":
        lines = [_option(theme, str(index), workload.title) for index, workload in enumerate(WORKLOADS, start=1)]
        body = [_blank(theme), *lines, _blank(theme), _back_line(theme)]
        return "\n".join([_frame(theme, "Workloads", body), ""])
    body = [
        _blank(theme),
        _option(theme, "1", "Start"),
        _option(theme, "2", "Scale to"),
        _option(theme, "3", "Update"),
        _option(theme, "4", "Logs"),
        _blank(theme),
        _back_line(theme),
    ]
    return "\n".join([_frame(theme, state.workload_key or "", body), ""])


def _parse_replica_count(text: str) -> int | None:
    stripped = text.strip()
    if not stripped.isdigit():
        return None
    return int(stripped)


def run_menu(read_line: Callable[[], str], write: Callable[[str], None], on_run: Callable[[MenuState], int]) -> int:
    state: MenuState | None = MenuState("root")
    while state is not None:
        if state.screen == "run":
            action = state.action
            cluster_name = state.cluster_name
            workload_key = state.workload_key
            on_run(state)
            if workload_key:
                state = MenuState("action", cluster_name, workload_key)
            else:
                state = MenuState("environment", cluster_name)
            continue
        write(render(state))
        choice = read_line()
        if state.screen == "scale_prompt":
            if not choice.strip():
                if state.workload_key:
                    state = MenuState("action", state.cluster_name, state.workload_key)
                else:
                    state = MenuState("environment", state.cluster_name)
                continue
            replicas = _parse_replica_count(choice)
            if replicas is None:
                continue
            action = "escalar-workload" if state.workload_key else "escalar-ambiente"
            on_run(
                MenuState(
                    "run",
                    state.cluster_name,
                    state.workload_key,
                    action,
                    replicas=replicas,
                )
            )
            if state.workload_key:
                state = MenuState("action", state.cluster_name, state.workload_key)
            else:
                state = MenuState("environment", state.cluster_name)
            continue
        state = next_state(state, choice)
    return 0
