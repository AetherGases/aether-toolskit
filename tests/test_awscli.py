from aether_env.awscli import (
    aws_process_env,
    cluster_config,
    create_cluster_args,
    delete_ecr_args,
    describe_nodegroup_desired_size_args,
    ecr_repository,
    image_uri,
    delete_stack_args,
    list_eks_cluster_security_group_ids_args,
    list_eksctl_stack_names_args,
    stack_vpc_physical_id_args,
    update_nodegroup_scaling_args,
    wait_nodegroup_active_args,
)
from aether_env.config import load_settings


def test_nodegroup_scaling_update_and_wait():
    update = update_nodegroup_scaling_args("sa-east-1", "aether-qa", "ng", 0, 1, 0)
    assert update[:3] == ["aws", "eks", "update-nodegroup-config"]
    assert "--scaling-config" in update
    assert update[update.index("--scaling-config") + 1] == "minSize=0,maxSize=1,desiredSize=0"
    desired = describe_nodegroup_desired_size_args("sa-east-1", "aether-qa", "ng")
    assert desired[:3] == ["aws", "eks", "describe-nodegroup"]
    assert "nodegroup.scalingConfig.desiredSize" in desired[desired.index("--query") + 1]
    wait = wait_nodegroup_active_args("sa-east-1", "aether-qa", "ng")
    assert wait[:4] == ["aws", "eks", "wait", "nodegroup-active"]


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


def test_stack_vpc_and_eks_security_group_queries():
    vpc = stack_vpc_physical_id_args("us-east-1", "eksctl-aether-qa-cluster")
    assert "LogicalResourceId=='VPC'" in vpc[vpc.index("--query") + 1]
    groups = list_eks_cluster_security_group_ids_args("us-east-1", "vpc-123", "aether-qa")
    assert "eks-cluster-sg-aether-qa-" in groups[groups.index("--query") + 1]


def test_delete_stack_can_retain_blocked_resources():
    args = delete_stack_args("us-east-1", "eksctl-aether-qa-cluster", ["LatticeService", "LatticeTarget"])
    assert args.count("--retain-resources") == 2
    assert "LatticeService" in args
    assert "LatticeTarget" in args


def test_list_eksctl_stack_names_filters_by_cluster_prefix():
    args = list_eksctl_stack_names_args("us-east-1", "aether-qa")
    assert "list-stacks" in args
    query = args[args.index("--query") + 1]
    assert "eksctl-aether-qa" in query


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
