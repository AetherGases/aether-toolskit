from pathlib import Path

from aether_env.catalog import get_workload
from aether_env.images import docker_build_args, dockerfile_for, sync_main_commands


def test_sync_clones_main_or_fetches_it():
    clone = sync_main_commands("aether-ms-auth", "C:/src", False, "develop")
    assert clone[0][:4] == ["git", "clone", "--branch", "develop"]
    update = sync_main_commands("aether-ms-auth", "C:/src", True, "main")
    assert "main" in update[0]
    assert update[0][:5] == ["git", "-C", "C:/src", "fetch", "--depth"]
    assert update[1][-1] == "FETCH_HEAD"


def test_toolkit_dockerfile_and_build_args():
    workload = get_workload("aether-web-flow")
    path = dockerfile_for(Path("C:/kit"), workload, Path("C:/src"))
    assert path == Path("C:/kit/dockerfiles/aether-web-flow/Dockerfile")
    args = docker_build_args(str(path), "C:/src", ["img:main"], {"API_URL": "http://lb"})
    assert "--build-arg" in args
    assert "API_URL=http://lb" in args
    assert args[-1] == "C:/src"
