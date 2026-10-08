from aether_env.preflight import missing_tools
from aether_env.runner import CommandResult


def test_missing_tools_reports_absent_names():
    found = {"aws": "aws", "git": "git"}
    assert missing_tools(lambda name: found.get(name)) == ("eksctl", "kubectl", "docker")


def test_command_result_keeps_args():
    result = CommandResult(("aws", "sts"), 0, "123", "")
    assert result.stdout == "123"
