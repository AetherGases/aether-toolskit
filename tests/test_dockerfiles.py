from pathlib import Path

from aether_env.catalog import WORKLOADS
from aether_env.images import dockerfile_for


ROOT = Path(__file__).resolve().parents[1]


def test_toolkit_dockerfiles_exist_and_name_the_process():
    expected = {
        "ms-aeko-hub": "uvicorn",
        "aether-rpa": "src.worker",
        "aether-web-flow": "API_URL",
        "aether-web-administrative": "catalina.sh",
    }
    for workload in WORKLOADS:
        if workload.kind != "app" or workload.dockerfile_in_repo:
            continue
        path = dockerfile_for(ROOT, workload, ROOT / "unused")
        text = path.read_text(encoding="utf-8")
        assert expected[workload.key] in text
        if workload.key != "aether-web-flow":
            assert "/app/.env" in text
