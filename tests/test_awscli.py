from aether_env.awscli import (
    aws_process_env,
    cluster_config,
    create_cluster_args,
    delete_ecr_args,
    ecr_repository,
    image_uri,
)
from aether_env.config import load_settings


def test_create_cluster_uses_managed_nodegroup():
    args = create_cluster_args("sa-east-1", "aether-qa", "t3.large", 2)
    assert args[:4] == ["eksctl", "create", "cluster", "--name"]
    assert "aether-qa" in args
    assert "--managed" in args
    assert args[args.index("--nodes") + 1] == "2"


def test_cluster_config_uses_roles_from_the_environment():
    text = cluster_config(
        "us-east-1",
        "aether-qa",
        "t3.large",
        2,
        "arn:aws:iam::123:role/cluster",
        "arn:aws:iam::123:role/node",
    )
    args = create_cluster_args("us-east-1", "aether-qa", "t3.large", 2, "cluster.yaml")
    assert args == ["eksctl", "create", "cluster", "--config-file", "cluster.yaml"]
    assert "serviceRoleARN: arn:aws:iam::123:role/cluster" in text
    assert "instanceRoleARN: arn:aws:iam::123:role/node" in text


def test_ecr_names_and_env_do_not_keep_a_stale_session_token():
    assert ecr_repository("qa", "aether-ms-auth") == "aether/qa/aether-ms-auth"
    assert image_uri("123", "sa-east-1", "aether/qa/aether-ms-auth", "main").endswith(":main")
    settings = load_settings({
        "AWS_ACCESS_KEY_ID": "aki",
        "AWS_SECRET_ACCESS_KEY": "secret",
        "AWS_REGION": "sa-east-1",
        "POSTGRES_USER": "sa",
        "POSTGRES_PASSWORD": "pw",
        "POSTGRES_DB_FIRST_YEAR": "a",
        "POSTGRES_DB_SECOND_YEAR": "b",
        "MONGO_USER": "mongo",
        "MONGO_PASSWORD": "mp",
        "MONGO_DB": "db",
        "REDIS_PASSWORD": "rp",
        "JWT_SECRET": "jwt",
    })
    env = aws_process_env(settings, {"AWS_SESSION_TOKEN": "old", "PATH": "/usr/bin"})
    assert "AWS_SESSION_TOKEN" not in env
    assert env["AWS_REGION"] == "sa-east-1"
    delete = delete_ecr_args("sa-east-1", "aether/qa/aether-ms-auth")
    assert "--force" in delete
