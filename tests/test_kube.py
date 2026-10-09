from aether_env.kube import (
    INGRESS_NGINX_URL,
    ingress_nginx_rollout_status_args,
    rollout_restart_args,
    scale_args,
    set_image_args,
)


def test_scale_and_image_and_ingress_pin():
    assert scale_args("C:/kube", "statefulset", "postgres", 0)[-2:] == ["statefulset/postgres", "--replicas=0"]
    assert "deployment/aether-ms-auth" in set_image_args("C:/kube", "aether-ms-auth", "img:main")
    assert rollout_restart_args("C:/kube", "redis")[-1] == "statefulset/redis"
    assert INGRESS_NGINX_URL.endswith("controller-v1.11.3/deploy/static/provider/aws/deploy.yaml")
    rollout = ingress_nginx_rollout_status_args("C:/kube")
    assert rollout[-2:] == ["deployment/ingress-nginx-controller", "--timeout=300s"]
