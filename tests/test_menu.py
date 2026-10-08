from aether_env.menu import MenuState, next_state, render, run_menu
from aether_env.theme import PROD, QA


def test_root_render_colors():
    text = render(MenuState("root"))
    assert f"{QA.accent}QA{QA.reset}" in text
    assert f"{PROD.accent}Production{PROD.reset}" in text


def test_qa_confirm_render_colors():
    text = render(MenuState("confirm-teardown", "aether-qa"))
    assert f"{QA.accent}aether-qa{QA.reset}" in text
    assert f"{QA.text} deletes the cluster, disks, and data.{QA.reset}" in text
    assert (
        f"{QA.accent}Tear down {QA.accent}aether-qa{QA.reset}{QA.text} deletes the cluster, disks, and data.{QA.reset}"
        in text
    )


def test_qa_environment_option_zero_is_blue():
    text = render(MenuState("environment", "aether-qa"))
    assert f"{QA.accent}0{QA.reset} {QA.text}Back{QA.reset}" in text


def test_qa_environment_is_blue_and_white():
    text = render(MenuState("environment", "aether-qa"))
    assert "\033[94m" in text
    assert "\033[97m" in text
    assert "\033[91m" not in text
    assert "Start environment" in text
    assert "Tear down environment" in text


def test_prod_environment_is_red_and_white():
    text = render(MenuState("environment", "aether-prod"))
    assert "\033[91m" in text
    assert "\033[97m" in text
    assert "\033[94m" not in text


def test_navigation_and_actions():
    qa = next_state(MenuState("root"), "1")
    assert qa == MenuState("environment", "aether-qa")
    workloads = next_state(qa, "3")
    assert workloads.screen == "workloads"
    auth = next_state(workloads, "1")
    assert auth.workload_key == "aether-ms-auth"
    update = next_state(auth, "3")
    assert update.action == "update"
    assert next_state(MenuState("root"), "0") is None


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
