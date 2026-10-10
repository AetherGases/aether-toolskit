from aether_env.kube import (
    INGRESS_NGINX_URL,
    delete_pvc_args,
    delete_resource_args,
    ingress_nginx_rollout_status_args,
    logs_follow_args,
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


def test_logs_follow_one_workload_or_all():
    one = logs_follow_args("C:/kube", "app=postgres")
    assert one[:3] == ["kubectl", "--kubeconfig", "C:/kube"]
    assert "-f" in one
    assert "--all-containers" in one
    assert "--prefix" in one
    assert one[one.index("-l") + 1] == "app=postgres"
    all_logs = logs_follow_args("C:/kube", None)
    assert all_logs[all_logs.index("-l") + 1] == "app"
    assert "--max-log-requests=20" in all_logs
    assert delete_resource_args("C:/kube", "statefulset/postgres")[-2] == "statefulset/postgres"
    assert "--ignore-not-found" in delete_pvc_args("C:/kube", "data-postgres-0")
