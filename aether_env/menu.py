from collections.abc import Callable
from dataclasses import dataclass

from aether_env.catalog import WORKLOADS
from aether_env.confirm import required_phrase
from aether_env.theme import PROD, QA, theme_for


@dataclass(frozen=True)
class MenuState:
    screen: str
    cluster_name: str | None = None
    workload_key: str | None = None
    action: str | None = None


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
            return MenuState("confirm-teardown", state.cluster_name)
        if choice == "3":
            return MenuState("workloads", state.cluster_name)
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
        actions = {"1": "subir", "2": "derrubar", "3": "update"}
        if choice in actions:
            return MenuState("run", state.cluster_name, state.workload_key, actions[choice])
        if choice == "0":
            return MenuState("workloads", state.cluster_name)
        return state
    return state


def _back_line(theme) -> str:
    return f"{theme.accent}0{theme.reset} {theme.text}Back{theme.reset}"


def _phrase_line(theme) -> str:
    phrase = required_phrase(theme.cluster_name)
    if phrase == theme.cluster_name:
        phrase_colored = f"{theme.accent}{phrase}{theme.reset}"
    else:
        phrase_colored = f"{theme.text}{phrase}{theme.reset}"
    return f"{theme.text}Type {phrase_colored}{theme.reset}"


def render(state: MenuState) -> str:
    if state.screen == "root":
        return "\n".join([
            f"{QA.text}Aether{QA.reset}",
            f"{QA.accent}1{QA.reset} {QA.accent}QA{QA.reset}",
            f"{PROD.accent}2{PROD.reset} {PROD.accent}Production{PROD.reset}",
            f"{QA.text}0 Exit{QA.reset}",
            "",
        ])
    theme = theme_for(state.cluster_name or "")
    if state.screen == "environment":
        lines = [
            f"{theme.accent}{theme.cluster_name}{theme.reset}",
            f"{theme.accent}1{theme.reset} {theme.text}Start environment{theme.reset}",
            f"{theme.accent}2{theme.reset} {theme.text}Tear down environment{theme.reset}",
            f"{theme.accent}3{theme.reset} {theme.text}Choose workload{theme.reset}",
            _back_line(theme),
        ]
    elif state.screen == "workloads":
        lines = [f"{theme.accent}Workloads{theme.reset}"]
        for index, workload in enumerate(WORKLOADS, start=1):
            lines.append(
                f"{theme.accent}{index}{theme.reset} {theme.accent}{workload.title}{theme.reset}"
            )
        lines.append(_back_line(theme))
    elif state.screen == "confirm-teardown":
        lines = [
            (
                f"{theme.accent}Tear down {theme.accent}{theme.cluster_name}{theme.reset}"
                f"{theme.text} deletes the cluster, disks, and data.{theme.reset}"
            ),
            _phrase_line(theme),
        ]
    else:
        lines = [
            f"{theme.accent}{state.workload_key}{theme.reset}",
            f"{theme.accent}1{theme.reset} {theme.text}Start{theme.reset}",
            f"{theme.accent}2{theme.reset} {theme.text}Tear down{theme.reset}",
            f"{theme.accent}3{theme.reset} {theme.text}Update{theme.reset}",
            _back_line(theme),
        ]
    return "\n".join(lines) + "\n"


def run_menu(read_line: Callable[[], str], write: Callable[[str], None], on_run: Callable[[MenuState], int], on_confirm: Callable[[str, str], int]) -> int:
    state: MenuState | None = MenuState("root")
    while state is not None:
        if state.screen == "run":
            on_run(state)
            if state.workload_key:
                state = MenuState("action", state.cluster_name, state.workload_key)
            else:
                state = MenuState("environment", state.cluster_name)
            continue
        write(render(state))
        choice = read_line()
        if state.screen == "confirm-teardown":
            on_confirm(state.cluster_name or "", choice)
            state = MenuState("environment", state.cluster_name)
            continue
        state = next_state(state, choice)
    return 0
