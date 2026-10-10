from aether_env.menu import MenuState, next_state, render, run_menu
from aether_env.theme import PROD, QA


def test_root_render_colors():
    text = render(MenuState("root"))
    assert f"{QA.accent}QA{QA.reset}" in text
    assert f"{PROD.accent}Production{PROD.reset}" in text


def test_qa_environment_option_zero_is_blue():
    text = render(MenuState("environment", "aether-qa"))
    assert f"{QA.accent}0{QA.reset}  {QA.text}Back{QA.reset}" in text


def test_qa_environment_is_blue_and_white():
    text = render(MenuState("environment", "aether-qa"))
    assert "\033[94m" in text
    assert "\033[97m" in text
    assert "\033[91m" not in text
    assert "Start environment" in text
    assert "Tear down environment" not in text
    assert "Scale to zero" in text
    assert "Scale to one" in text
    assert "Logs" in text
    assert "Container status" in text


def test_prod_environment_is_red_and_white():
    text = render(MenuState("environment", "aether-prod"))
    assert "\033[91m" in text
    assert "\033[97m" in text
    assert "\033[94m" not in text
    assert "Scale to zero" in text
    assert "Scale to one" in text
    assert "Tear down environment" not in text
    assert "Logs" in text
    assert "Container status" in text


def test_frame_lines_have_single_border():
    for state in (
        MenuState("root"),
        MenuState("environment", "aether-qa"),
        MenuState("workloads", "aether-qa"),
        MenuState("logs", "aether-qa"),
        MenuState("action", "aether-qa", "kong"),
    ):
        for line in render(state).splitlines():
            if "╭" in line or "╰" in line:
                continue
            assert line.count("│") == 2


def test_workloads_are_grouped_by_kind():
    text = render(MenuState("workloads", "aether-qa"))
    assert f"{QA.dim}Applications{QA.reset}" in text
    assert f"{QA.dim}Databases{QA.reset}" in text
    assert text.index("Applications") < text.index("Kong Gateway")
    assert text.index("Databases") < text.index("Postgres")


def test_navigation_and_actions():
    qa = next_state(MenuState("root"), "1")
    assert qa == MenuState("environment", "aether-qa")
    workloads = next_state(qa, "4")
    assert workloads.screen == "workloads"
    auth = next_state(workloads, "2")
    assert auth.workload_key == "aether-ms-auth"
    update = next_state(auth, "4")
    assert update.action == "update"
    scale_env = next_state(qa, "2")
    assert scale_env == MenuState("run", "aether-qa", action="escalar-ambiente-zero")
    scale_env_one = next_state(qa, "3")
    assert scale_env_one == MenuState("run", "aether-qa", action="escalar-ambiente-um")
    scale_item = next_state(auth, "2")
    assert scale_item.action == "escalar-zero"
    scale_item_one = next_state(auth, "3")
    assert scale_item_one.action == "escalar-um"
    logs = next_state(qa, "5")
    assert logs == MenuState("logs", "aether-qa")
    status = next_state(qa, "6")
    assert status == MenuState("run", "aether-qa", action="status")
    all_logs = next_state(logs, "1")
    assert all_logs == MenuState("run", "aether-qa", action="logs")
    kong_logs = next_state(logs, "2")
    assert kong_logs == MenuState("run", "aether-qa", "kong", "logs")
    assert next_state(logs, "0") == qa
    assert next_state(MenuState("root"), "0") is None


def test_action_menu_has_scale_to_zero_without_teardown():
    text = render(MenuState("action", "aether-qa", "kong"))
    assert "Start" in text
    assert "Tear down" not in text
    assert "Update" in text
    assert "Scale to zero" in text
    assert "Scale to one" in text


def test_logs_menu_lists_all_then_workloads():
    text = render(MenuState("logs", "aether-qa"))
    assert "All" in text
    assert "Kong Gateway" in text
    assert "Postgres" in text
    assert "Start" not in text


def test_run_menu_returns_to_logs_after_follow():
    seen = []
    lines = iter(["1", "5", "1", "0", "0", "0"])
    writes = []

    def on_run(state):
        seen.append(state.action)
        return 0

    code = run_menu(lambda: next(lines), writes.append, on_run)
    assert code == 0
    assert seen == ["logs"]
    assert any("Logs" in item for item in writes)


def test_run_menu_scale_to_zero_from_environment():
    seen = []
    lines = iter(["1", "2", "0", "0"])
    writes = []

    def on_run(state):
        seen.append(state.action)
        return 0

    code = run_menu(lambda: next(lines), writes.append, on_run)
    assert code == 0
    assert seen == ["escalar-ambiente-zero"]
    assert any("Scale to zero" in item for item in writes)
