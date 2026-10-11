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
    assert "Scale to" in text
    assert "Scale to zero" not in text
    assert "Logs" not in text
    assert "Container status" in text


def test_prod_environment_is_red_and_white():
    text = render(MenuState("environment", "aether-prod"))
    assert "\033[91m" in text
    assert "\033[97m" in text
    assert "\033[94m" not in text
    assert "Scale to" in text
    assert "Tear down environment" not in text
    assert "Logs" not in text
    assert "Container status" in text


def test_frame_lines_have_single_border():
    for state in (
        MenuState("root"),
        MenuState("environment", "aether-qa"),
        MenuState("workloads", "aether-qa"),
        MenuState("scale_prompt", "aether-qa"),
        MenuState("action", "aether-qa", "kong"),
    ):
        for line in render(state).splitlines():
            if "╭" in line or "╰" in line:
                continue
            assert line.count("│") == 2


def test_workloads_lists_catalog_in_order():
    text = render(MenuState("workloads", "aether-qa"))
    assert "Kong Gateway" in text
    assert "Postgres" not in text
    assert text.index("Kong Gateway") < text.index("aether-ms-auth")


def test_navigation_and_actions():
    qa = next_state(MenuState("root"), "1")
    assert qa == MenuState("environment", "aether-qa")
    workloads = next_state(qa, "3")
    assert workloads.screen == "workloads"
    auth = next_state(workloads, "2")
    assert auth.workload_key == "aether-ms-auth"
    update = next_state(auth, "3")
    assert update.action == "update"
    scale_env = next_state(qa, "2")
    assert scale_env == MenuState("scale_prompt", "aether-qa")
    scale_item = next_state(auth, "2")
    assert scale_item == MenuState("scale_prompt", "aether-qa", "aether-ms-auth")
    kong_logs = next_state(auth, "4")
    assert kong_logs == MenuState("run", "aether-qa", "aether-ms-auth", "logs")
    status = next_state(qa, "4")
    assert status == MenuState("run", "aether-qa", action="status")
    assert next_state(MenuState("root"), "0") is None


def test_action_menu_has_scale_and_logs():
    text = render(MenuState("action", "aether-qa", "kong"))
    assert "Start" in text
    assert "Tear down" not in text
    assert "Update" in text
    assert "Scale to" in text
    assert "Scale to zero" not in text
    assert "Logs" in text


def test_run_menu_returns_to_workload_after_logs():
    seen = []
    lines = iter(["1", "3", "2", "4", "0", "0", "0", "0"])
    writes = []

    def on_run(state):
        seen.append((state.action, state.workload_key))
        return 0

    code = run_menu(lambda: next(lines), writes.append, on_run)
    assert code == 0
    assert ("logs", "aether-ms-auth") in seen


def test_run_menu_scale_environment_from_prompt():
    seen = []
    lines = iter(["1", "2", "0", "0", "0"])
    writes = []

    def on_run(state):
        seen.append((state.action, state.replicas))
        return 0

    code = run_menu(lambda: next(lines), writes.append, on_run)
    assert code == 0
    assert ("escalar-ambiente", 0) in seen
    assert any("Replica count" in item for item in writes)
