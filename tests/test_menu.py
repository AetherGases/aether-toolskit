from aether_env.menu import MenuState, next_state, render, run_menu
from aether_env.theme import PROD, QA


def test_root_render_colors():
    text = render(MenuState("root"))
    assert f"{QA.accent}QA{QA.reset}" in text
    assert f"{PROD.accent}Production{PROD.reset}" in text


def test_qa_confirm_render_colors():
    text = render(MenuState("confirm-teardown", "aether-qa"))
    assert f"{QA.accent}aether-qa{QA.reset}" in text
    assert f"{QA.text}This deletes {QA.accent}aether-qa{QA.reset}{QA.text}, disks, and data.{QA.reset}" in text
    assert "Tear down" in text


def test_qa_environment_option_zero_is_blue():
    text = render(MenuState("environment", "aether-qa"))
    assert f"{QA.accent}0{QA.reset}  {QA.text}Back{QA.reset}" in text


def test_qa_environment_is_blue_and_white():
    text = render(MenuState("environment", "aether-qa"))
    assert "\033[94m" in text
    assert "\033[97m" in text
    assert "\033[91m" not in text
    assert "Start environment" in text
    assert "Tear down environment" in text
    assert "Scale to zero" in text


def test_prod_environment_is_red_and_white():
    text = render(MenuState("environment", "aether-prod"))
    assert "\033[91m" in text
    assert "\033[97m" in text
    assert "\033[94m" not in text
    assert "Scale to zero" in text
    assert "Tear down environment" in text


def test_frame_lines_have_single_border():
    for state in (
        MenuState("root"),
        MenuState("environment", "aether-qa"),
        MenuState("workloads", "aether-qa"),
        MenuState("confirm-teardown", "aether-qa"),
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
    workloads = next_state(qa, "3")
    assert workloads.screen == "workloads"
    auth = next_state(workloads, "2")
    assert auth.workload_key == "aether-ms-auth"
    update = next_state(auth, "3")
    assert update.action == "update"
    scale_env = next_state(qa, "4")
    assert scale_env == MenuState("run", "aether-qa", action="escalar-ambiente-zero")
    scale_item = next_state(auth, "4")
    assert scale_item.action == "escalar-zero"
    assert next_state(MenuState("root"), "0") is None


def test_action_menu_keeps_teardown_and_adds_scale_to_zero():
    text = render(MenuState("action", "aether-qa", "kong"))
    assert "Start" in text
    assert "Tear down" in text
    assert "Update" in text
    assert "Scale to zero" in text


def test_run_menu_asks_phrase_before_teardown():
    seen = []
    lines = iter(["2", "2", "nope", "0", "0"])
    writes = []

    def on_confirm(cluster, phrase):
        seen.append((cluster, phrase))
        return 0

    code = run_menu(lambda: next(lines), writes.append, lambda state: 0, on_confirm)
    assert code == 0
    assert seen == [("aether-prod", "nope")]
    assert any("aether-prod" in item for item in writes)
