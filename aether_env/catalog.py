from dataclasses import dataclass


@dataclass(frozen=True)
class Workload:
    key: str
    title: str
    kind: str
    repo: str | None
    container_port: int | None
    k8s_kind: str
    ingress_path: str | None
    image: str | None
    dockerfile_in_repo: bool


WORKLOADS: tuple[Workload, ...] = (
    Workload("kong", "Kong Gateway", "app", None, 8000, "deployment", "/", None, False),
    Workload("aether-ms-auth", "aether-ms-auth", "app", "aether-ms-auth", 8080, "deployment", None, None, True),
    Workload("aether-ms-calculator", "aether-ms-calculator", "app", "aether-ms-calculator", 8080, "deployment", None, None, True),
    Workload("aether-ms-inventory", "aether-ms-inventory", "app", "aether-ms-inventory", 8080, "deployment", None, None, True),
    Workload("aether-ms-cloudinary", "aether-ms-cloudinary", "app", "aether-ms-cloudinary", 8080, "deployment", None, None, True),
    Workload("ms-aeko-hub", "ms-aeko-hub", "app", "ms-aeko-hub", 8000, "deployment", None, None, False),
    Workload("aether-rpa", "aether-rpa", "app", "aether-rpa", None, "deployment", None, None, False),
    Workload("aether-web-flow", "aether-web-flow", "app", "aether-web-flow", 80, "deployment", None, None, False),
    Workload("aether-web-administrative", "aether-web-administrative", "app", "aether-web-administrative", 8080, "deployment", None, None, False),
    Workload("postgres", "Postgres", "database", None, 5432, "statefulset", None, "postgres:16.10", False),
    Workload("mongo", "Mongo", "database", None, 27017, "statefulset", None, "mongo:8.0.13", False),
    Workload("redis", "Redis", "database", None, 6379, "statefulset", None, "redis:8.2", False),
)


def get_workload(key: str) -> Workload:
    for workload in WORKLOADS:
        if workload.key == key:
            return workload
    raise KeyError(key)
