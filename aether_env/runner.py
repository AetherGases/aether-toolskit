import subprocess
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class CommandResult:
    args: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str


class SubprocessRunner:
    def run(
        self,
        args: Sequence[str],
        *,
        env: Mapping[str, str] | None = None,
        cwd: Path | None = None,
        stdin: str | None = None,
        stream: bool = False,
    ) -> CommandResult:
        completed = subprocess.run(
            list(args),
            env=None if env is None else dict(env),
            cwd=cwd,
            input=stdin,
            text=True,
            capture_output=not stream,
        )
        return CommandResult(
            tuple(args),
            completed.returncode,
            "" if stream else completed.stdout,
            "" if stream else completed.stderr,
        )
