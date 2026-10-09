import os

from aether_env.preflight import ensure_cli_on_path, missing_tools
from aether_env.runner import CommandResult


def test_ensure_cli_on_path_prepends_windows_install_dirs(tmp_path, monkeypatch):
    aws_dir = tmp_path / "Amazon" / "AWSCLIV2"
    aws_dir.mkdir(parents=True)
    packages = tmp_path / "Microsoft" / "WinGet" / "Packages" / "eksctl.eksctl_Microsoft.Winget.Source_8wekyb3d8bbwe"
    packages.mkdir(parents=True)
    monkeypatch.setenv("PROGRAMFILES", str(tmp_path))
    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path))
    monkeypatch.setenv("PATH", r"C:\existing")
    ensure_cli_on_path()
    parts = os.environ["PATH"].split(os.pathsep)
    assert str(aws_dir) in parts
    assert str(packages) in parts


def test_missing_tools_reports_absent_names():
    found = {"aws": "aws", "git": "git"}
    assert missing_tools(lambda name: found.get(name)) == ("eksctl", "kubectl", "docker")


def test_command_result_keeps_args():
    result = CommandResult(("aws", "sts"), 0, "123", "")
    assert result.stdout == "123"
