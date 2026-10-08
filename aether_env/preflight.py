import shutil
from collections.abc import Callable


REQUIRED_TOOLS = ("aws", "eksctl", "kubectl", "docker", "git")


def missing_tools(lookup: Callable[[str], str | None] = shutil.which) -> tuple[str, ...]:
    return tuple(name for name in REQUIRED_TOOLS if lookup(name) is None)
