import os
import shutil
from collections.abc import Callable
from pathlib import Path


REQUIRED_TOOLS = ("aws", "eksctl", "kubectl", "docker", "git")


def ensure_cli_on_path() -> None:
    extra: list[str] = []
    aws_dir = Path(os.environ.get("PROGRAMFILES", r"C:\Program Files")) / "Amazon" / "AWSCLIV2"
    if aws_dir.is_dir():
        extra.append(str(aws_dir))
    packages = Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft" / "WinGet" / "Packages"
    if packages.is_dir():
        for child in packages.iterdir():
            if child.is_dir() and "eksctl" in child.name.lower():
                extra.append(str(child))
    if not extra:
        return
    parts = os.environ.get("PATH", "").split(os.pathsep)
    for directory in reversed(extra):
        if directory not in parts:
            parts.insert(0, directory)
    os.environ["PATH"] = os.pathsep.join(parts)


def missing_tools(lookup: Callable[[str], str | None] = shutil.which) -> tuple[str, ...]:
    ensure_cli_on_path()
    return tuple(name for name in REQUIRED_TOOLS if lookup(name) is None)
