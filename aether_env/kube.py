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
