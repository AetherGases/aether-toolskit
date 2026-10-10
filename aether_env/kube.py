INGRESS_NGINX_URL = (
    "https://raw.githubusercontent.com/kubernetes/ingress-nginx/"
    "controller-v1.11.3/deploy/static/provider/aws/deploy.yaml"
)


def _base(kubeconfig: str) -> list[str]:
    return ["kubectl", "--kubeconfig", kubeconfig]


def apply_stdin_args(kubeconfig: str) -> list[str]:
    return _base(kubeconfig) + ["apply", "-f", "-"]


def apply_url_args(kubeconfig: str, url: str) -> list[str]:
    return _base(kubeconfig) + ["apply", "-f", url]


def scale_args(kubeconfig: str, k8s_kind: str, name: str, replicas: int) -> list[str]:
    return _base(kubeconfig) + ["-n", "aether", "scale", f"{k8s_kind}/{name}", f"--replicas={replicas}"]


def set_image_args(kubeconfig: str, name: str, image: str) -> list[str]:
    return _base(kubeconfig) + [
        "-n", "aether", "set", "image", f"deployment/{name}", f"{name}={image}",
    ]


def rollout_status_args(kubeconfig: str, k8s_kind: str, name: str) -> list[str]:
    return _base(kubeconfig) + [
        "-n", "aether", "rollout", "status", f"{k8s_kind}/{name}", "--timeout=180s",
    ]


def rollout_restart_args(kubeconfig: str, name: str) -> list[str]:
    return _base(kubeconfig) + ["-n", "aether", "rollout", "restart", f"statefulset/{name}"]


def get_pods_args(kubeconfig: str) -> list[str]:
    return _base(kubeconfig) + ["-n", "aether", "get", "pods"]


def delete_resource_args(kubeconfig: str, resource: str) -> list[str]:
    return _base(kubeconfig) + ["-n", "aether", "delete", resource, "--ignore-not-found"]


def delete_pvc_args(kubeconfig: str, name: str) -> list[str]:
    return _base(kubeconfig) + ["-n", "aether", "delete", "pvc", name, "--ignore-not-found"]


def logs_follow_args(kubeconfig: str, selector: str | None = None) -> list[str]:
    args = _base(kubeconfig) + [
        "-n", "aether", "logs", "-f",
        "--all-containers", "--prefix", "--tail=100",
        "-l", selector or "app",
    ]
    if selector is None:
        args.append("--max-log-requests=20")
    return args


def ingress_nginx_rollout_status_args(kubeconfig: str) -> list[str]:
    return _base(kubeconfig) + [
        "-n", "ingress-nginx", "rollout", "status",
        "deployment/ingress-nginx-controller", "--timeout=300s",
    ]


def ingress_hostname_args(kubeconfig: str) -> list[str]:
    return _base(kubeconfig) + [
        "-n", "ingress-nginx", "get", "svc", "ingress-nginx-controller",
        "-o", "jsonpath={.status.loadBalancer.ingress[0].hostname}",
    ]


def ingress_ip_args(kubeconfig: str) -> list[str]:
    return _base(kubeconfig) + [
        "-n", "ingress-nginx", "get", "svc", "ingress-nginx-controller",
        "-o", "jsonpath={.status.loadBalancer.ingress[0].ip}",
    ]
