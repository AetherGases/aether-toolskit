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
    ingress = render_ingress([item for item in WORKLOADS if item.ingress_path])
    assert "rewrite-target: /$2" in ingress
    assert "path: /" in ingress
    assert "aether-web-flow" in ingress
    assert "aether-rpa" not in ingress
