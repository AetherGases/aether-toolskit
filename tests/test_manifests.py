from aether_env.catalog import WORKLOADS, get_workload
from aether_env.manifests import render_app, render_database, render_ingress, render_secret


def test_secret_quotes_password_and_hides_aws_key():
    text = render_secret({"POSTGRES_PASSWORD": "p:ss", "AWS_SECRET_ACCESS_KEY": "nope"})
    assert "stringData:" in text
    assert '"p:ss"' in text


def test_databases_use_pinned_images_and_apps_use_the_given_image():
    assert "postgres:16.10" in render_database(get_workload("postgres"))
    assert "mongo:8.0.13" in render_database(get_workload("mongo"))
    redis = render_database(get_workload("redis"))
    assert "redis:8.2" in redis
    assert "requirepass" in redis
    app = render_app(get_workload("aether-ms-auth"), "123.dkr.ecr.sa-east-1.amazonaws.com/aether/qa/aether-ms-auth:main")
    assert "containerPort: 8080" in app


def test_ingress_exposes_only_kong():
    kong = get_workload("kong")
    ingress = render_ingress([kong])
    assert "name: kong" in ingress
    assert "aether-apis" not in ingress
    assert "rewrite-target" not in ingress
    assert "aether-ms-auth" not in ingress


def test_app_services_are_cluster_ip_only():
    for workload in WORKLOADS:
        if workload.kind != "app" or workload.container_port is None:
            continue
        manifest = render_app(workload, "example:latest")
        assert "type: ClusterIP" in manifest
        assert "LoadBalancer" not in manifest
        assert "NodePort" not in manifest
