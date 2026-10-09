from dataclasses import dataclass


@dataclass(frozen=True)
class KongRoute:
    name: str
    path: str
    upstream_host: str
    upstream_port: int
    strip_path: bool


KONG_ROUTES: tuple[KongRoute, ...] = (
    KongRoute("aether-ms-auth", "/auth", "aether-ms-auth.aether.svc.cluster.local", 8080, True),
    KongRoute("aether-ms-calculator", "/calculator", "aether-ms-calculator.aether.svc.cluster.local", 8080, True),
    KongRoute("aether-ms-inventory", "/inventory", "aether-ms-inventory.aether.svc.cluster.local", 8080, True),
    KongRoute("aether-ms-cloudinary", "/cloudinary", "aether-ms-cloudinary.aether.svc.cluster.local", 8080, True),
    KongRoute("ms-aeko-hub", "/hub", "ms-aeko-hub.aether.svc.cluster.local", 8000, True),
    KongRoute("aether-web-administrative", "/admin", "aether-web-administrative.aether.svc.cluster.local", 8080, True),
    KongRoute("aether-web-flow", "/", "aether-web-flow.aether.svc.cluster.local", 80, False),
)


def render_kong_config() -> str:
    lines = ['_format_version: "3.0"', "services:"]
    for route in KONG_ROUTES:
        lines.extend([
            f"  - name: {route.name}",
            f"    url: http://{route.upstream_host}:{route.upstream_port}",
            "    routes:",
            f"      - name: {route.name}-route",
            "        paths:",
            f"          - {route.path}",
            f"        strip_path: {'true' if route.strip_path else 'false'}",
        ])
    return "\n".join(lines) + "\n"
