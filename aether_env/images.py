import hashlib
from collections.abc import Mapping
from pathlib import Path

from aether_env.catalog import Workload


def sync_main_commands(repo: str, dest: str, dest_exists: bool, branch: str) -> list[list[str]]:
    if not dest_exists:
        return [[
            "git", "clone", "--branch", branch, "--single-branch",
            f"https://github.com/AetherGases/{repo}.git", dest,
        ]]
    return [
        ["git", "-C", dest, "fetch", "--depth", "1", "origin", branch],
        ["git", "-C", dest, "checkout", "-B", branch, "FETCH_HEAD"],
    ]


def rev_parse_args(dest: str) -> list[str]:
    return ["git", "-C", dest, "rev-parse", "HEAD"]


def docker_context_content_sha(context_dir: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(context_dir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(context_dir).as_posix().encode()
        digest.update(rel)
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()[:12]


def docker_build_args(dockerfile: str, context: str, tags: list[str], build_args: Mapping[str, str]) -> list[str]:
    command = ["docker", "build", "-f", dockerfile]
    for key, value in build_args.items():
        command.extend(["--build-arg", f"{key}={value}"])
    for tag in tags:
        command.extend(["-t", tag])
    command.append(context)
    return command


def docker_push_args(tag: str) -> list[str]:
    return ["docker", "push", tag]


def dockerfile_for(root: Path, workload: Workload, clone: Path) -> Path:
    if workload.dockerfile_in_repo:
        return clone / "Dockerfile"
    return root / "dockerfiles" / workload.key / "Dockerfile"
