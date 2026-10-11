from pathlib import Path

from aether_env.catalog import get_workload
from aether_env.images import (
    combined_deploy_sha,
    docker_build_args,
    docker_context_content_sha,
    dockerfile_for,
    sync_main_commands,
)


def test_sync_clones_main_or_fetches_it():
    clone = sync_main_commands("aether-ms-auth", "C:/src", False, "develop")
    assert clone[0][:4] == ["git", "clone", "--branch", "develop"]
    update = sync_main_commands("aether-ms-auth", "C:/src", True, "main")
    assert "main" in update[0]
    assert update[0][:5] == ["git", "-C", "C:/src", "fetch", "--depth"]
    assert update[1][-1] == "FETCH_HEAD"


def test_combined_deploy_sha_includes_toolkit_context(tmp_path):
    context = tmp_path / "ms-aeko-hub"
    context.mkdir()
    (context / "Dockerfile").write_text("FROM python\n", encoding="utf-8")
    first = combined_deploy_sha("abc123", context)
    (context / "Dockerfile").write_text("FROM python:3.12\n", encoding="utf-8")
    second = combined_deploy_sha("abc123", context)
    assert first != second
    assert combined_deploy_sha("abc123", None) == combined_deploy_sha("abc123", None)


def test_docker_context_content_sha_changes_when_context_changes(tmp_path):
    context = tmp_path / "kong"
    context.mkdir()
    (context / "Dockerfile").write_text("FROM kong\n", encoding="utf-8")
    (context / "kong.yml").write_text("v1\n", encoding="utf-8")
    first = docker_context_content_sha(context)
    (context / "kong.yml").write_text("v2\n", encoding="utf-8")
    second = docker_context_content_sha(context)
    assert first != second
    assert len(first) == 12


def test_toolkit_dockerfile_and_build_args():
    workload = get_workload("aether-web-flow")
    path = dockerfile_for(Path("C:/kit"), workload, Path("C:/src"))
    assert path == Path("C:/kit/dockerfiles/aether-web-flow/Dockerfile")
    args = docker_build_args(str(path), "C:/src", ["img:main"], {"API_URL": "http://lb"})
    assert "--build-arg" in args
    assert "API_URL=http://lb" in args
    assert args[-1] == "C:/src"
