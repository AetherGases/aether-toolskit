from collections.abc import Mapping

from aether_env.config import Settings


def describe_cluster_args(region: str, cluster_name: str) -> list[str]:
    return [
        "aws", "eks", "describe-cluster",
        "--name", cluster_name,
        "--region", region,
        "--query", "cluster.status",
        "--output", "text",
    ]


def create_cluster_args(
    region: str,
    cluster_name: str,
    node_type: str,
    node_count: int,
    config_path: str | None = None,
) -> list[str]:
    if config_path:
        return ["eksctl", "create", "cluster", "--config-file", config_path]
    return [
        "eksctl", "create", "cluster",
        "--name", cluster_name,
        "--region", region,
        "--nodegroup-name", "ng",
        "--node-type", node_type,
        "--nodes", str(node_count),
        "--managed",
    ]


def cluster_config(
    region: str,
    cluster_name: str,
    node_type: str,
    node_count: int,
    service_role_arn: str,
    node_role_arn: str | None = None,
) -> str:
    node_iam = ""
    if node_role_arn:
        node_iam = f"    iam:\n      instanceRoleARN: {node_role_arn}\n"
    return (
        "apiVersion: eksctl.io/v1alpha5\n"
        "kind: ClusterConfig\n"
        "metadata:\n"
        f"  name: {cluster_name}\n"
        f"  region: {region}\n"
        "iam:\n"
        "  withOIDC: false\n"
        f"  serviceRoleARN: {service_role_arn}\n"
        "managedNodeGroups:\n"
        "  - name: ng\n"
        f"    instanceType: {node_type}\n"
        f"    desiredCapacity: {node_count}\n"
        f"    minSize: {node_count}\n"
        f"    maxSize: {node_count}\n"
        f"{node_iam}"
    )


def describe_stack_args(region: str, stack_name: str) -> list[str]:
    return [
        "aws", "cloudformation", "describe-stacks",
        "--stack-name", stack_name,
        "--region", region,
        "--query", "Stacks[0].StackStatus",
        "--output", "text",
    ]


def disable_stack_protection_args(region: str, stack_name: str) -> list[str]:
    return [
        "aws", "cloudformation", "update-termination-protection",
        "--no-enable-termination-protection",
        "--stack-name", stack_name,
        "--region", region,
    ]


def delete_stack_args(region: str, stack_name: str) -> list[str]:
    return ["aws", "cloudformation", "delete-stack", "--stack-name", stack_name, "--region", region]


def wait_stack_delete_args(region: str, stack_name: str) -> list[str]:
    return [
        "aws", "cloudformation", "wait", "stack-delete-complete",
        "--stack-name", stack_name,
        "--region", region,
    ]


def list_nodegroups_args(region: str, cluster_name: str) -> list[str]:
    return [
        "aws", "eks", "list-nodegroups",
        "--cluster-name", cluster_name,
        "--region", region,
        "--query", "nodegroups[]",
        "--output", "text",
    ]


def delete_nodegroup_args(region: str, cluster_name: str, nodegroup_name: str) -> list[str]:
    return [
        "aws", "eks", "delete-nodegroup",
        "--cluster-name", cluster_name,
        "--nodegroup-name", nodegroup_name,
        "--region", region,
    ]


def wait_nodegroup_deleted_args(region: str, cluster_name: str, nodegroup_name: str) -> list[str]:
    return [
        "aws", "eks", "wait", "nodegroup-deleted",
        "--cluster-name", cluster_name,
        "--nodegroup-name", nodegroup_name,
        "--region", region,
    ]


def delete_cluster_args(region: str, cluster_name: str) -> list[str]:
    return [
        "aws", "eks", "delete-cluster",
        "--name", cluster_name,
        "--region", region,
    ]


def wait_cluster_deleted_args(region: str, cluster_name: str) -> list[str]:
    return [
        "aws", "eks", "wait", "cluster-deleted",
        "--name", cluster_name,
        "--region", region,
    ]


def kubeconfig_args(region: str, cluster_name: str, kubeconfig: str) -> list[str]:
    return [
        "aws", "eks", "update-kubeconfig",
        "--name", cluster_name,
        "--region", region,
        "--kubeconfig", kubeconfig,
    ]


def caller_identity_args() -> list[str]:
    return ["aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text"]


def describe_ecr_args(region: str, repository: str) -> list[str]:
    return ["aws", "ecr", "describe-repositories", "--repository-names", repository, "--region", region]


def create_ecr_args(region: str, repository: str) -> list[str]:
    return ["aws", "ecr", "create-repository", "--repository-name", repository, "--region", region]


def delete_ecr_args(region: str, repository: str) -> list[str]:
    return ["aws", "ecr", "delete-repository", "--repository-name", repository, "--region", region, "--force"]


def ecr_password_args(region: str) -> list[str]:
    return ["aws", "ecr", "get-login-password", "--region", region]


def docker_login_args(registry: str) -> list[str]:
    return ["docker", "login", "--username", "AWS", "--password-stdin", registry]


def ecr_repository(slug: str, workload_key: str) -> str:
    return f"aether/{slug}/{workload_key}"


def image_uri(account: str, region: str, repository: str, tag: str) -> str:
    return f"{account}.dkr.ecr.{region}.amazonaws.com/{repository}:{tag}"


def aws_process_env(settings: Settings, base: Mapping[str, str]) -> dict[str, str]:
    env = dict(base)
    env.pop("AWS_SESSION_TOKEN", None)
    env["AWS_ACCESS_KEY_ID"] = settings.aws_access_key_id
    env["AWS_SECRET_ACCESS_KEY"] = settings.aws_secret_access_key
    env["AWS_REGION"] = settings.aws_region
    env["AWS_DEFAULT_REGION"] = settings.aws_region
    if settings.aws_session_token:
        env["AWS_SESSION_TOKEN"] = settings.aws_session_token
    return env
