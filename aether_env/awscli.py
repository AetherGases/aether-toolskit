from collections.abc import Mapping, Sequence

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


def list_eksctl_stack_names_args(region: str, cluster_name: str) -> list[str]:
    prefix = f"eksctl-{cluster_name}"
    return [
        "aws", "cloudformation", "list-stacks",
        "--region", region,
        "--stack-status-filter",
        "CREATE_IN_PROGRESS",
        "CREATE_FAILED",
        "CREATE_COMPLETE",
        "ROLLBACK_IN_PROGRESS",
        "ROLLBACK_FAILED",
        "ROLLBACK_COMPLETE",
        "DELETE_IN_PROGRESS",
        "DELETE_FAILED",
        "UPDATE_IN_PROGRESS",
        "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS",
        "UPDATE_COMPLETE",
        "UPDATE_ROLLBACK_IN_PROGRESS",
        "UPDATE_ROLLBACK_FAILED",
        "UPDATE_ROLLBACK_COMPLETE",
        "REVIEW_IN_PROGRESS",
        "IMPORT_IN_PROGRESS",
        "IMPORT_COMPLETE",
        "IMPORT_ROLLBACK_IN_PROGRESS",
        "IMPORT_ROLLBACK_FAILED",
        "IMPORT_ROLLBACK_COMPLETE",
        "--query", f"StackSummaries[?starts_with(StackName, '{prefix}')].StackName",
        "--output", "text",
    ]


def describe_stack_events_args(region: str, stack_name: str) -> list[str]:
    return [
        "aws", "cloudformation", "describe-stack-events",
        "--stack-name", stack_name,
        "--region", region,
        "--max-items", "5",
        "--query", "StackEvents[?ResourceStatusReason!=null].[LogicalResourceId,ResourceStatus,ResourceStatusReason]",
        "--output", "text",
    ]


def disable_stack_protection_args(region: str, stack_name: str) -> list[str]:
    return [
        "aws", "cloudformation", "update-termination-protection",
        "--no-enable-termination-protection",
        "--stack-name", stack_name,
        "--region", region,
    ]


def list_vpc_lattice_resource_ids_args(region: str, stack_name: str) -> list[str]:
    return [
        "aws", "cloudformation", "list-stack-resources",
        "--stack-name", stack_name,
        "--region", region,
        "--query", "StackResourceSummaries[?contains(ResourceType, 'VpcLattice')].LogicalResourceId",
        "--output", "text",
    ]


def list_delete_failed_resource_ids_args(region: str, stack_name: str) -> list[str]:
    return [
        "aws", "cloudformation", "list-stack-resources",
        "--stack-name", stack_name,
        "--region", region,
        "--query", "StackResourceSummaries[?ResourceStatus=='DELETE_FAILED'].LogicalResourceId",
        "--output", "text",
    ]


def delete_stack_args(
    region: str,
    stack_name: str,
    retain_resources: Sequence[str] = (),
) -> list[str]:
    command = ["aws", "cloudformation", "delete-stack", "--stack-name", stack_name, "--region", region]
    for logical_id in retain_resources:
        command.extend(["--retain-resources", logical_id])
    return command


def stack_vpc_physical_id_args(region: str, stack_name: str) -> list[str]:
    return [
        "aws", "cloudformation", "list-stack-resources",
        "--stack-name", stack_name,
        "--region", region,
        "--query", "StackResourceSummaries[?LogicalResourceId=='VPC'].PhysicalResourceId",
        "--output", "text",
    ]


def list_eks_cluster_security_group_ids_args(region: str, vpc_id: str, cluster_name: str) -> list[str]:
    prefix = f"eks-cluster-sg-{cluster_name}-"
    return [
        "aws", "ec2", "describe-security-groups",
        "--region", region,
        "--filters", f"Name=vpc-id,Values={vpc_id}",
        "--query", f"SecurityGroups[?starts_with(GroupName, '{prefix}')].GroupId",
        "--output", "text",
    ]


def list_eks_cluster_security_group_ids_by_name_args(region: str, cluster_name: str) -> list[str]:
    prefix = f"eks-cluster-sg-{cluster_name}-"
    return [
        "aws", "ec2", "describe-security-groups",
        "--region", region,
        "--filters", f"Name=group-name,Values={prefix}*",
        "--query", "SecurityGroups[].GroupId",
        "--output", "text",
    ]


def delete_security_group_args(region: str, group_id: str) -> list[str]:
    return ["aws", "ec2", "delete-security-group", "--group-id", group_id, "--region", region]


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


def describe_nodegroup_desired_size_args(region: str, cluster_name: str, nodegroup_name: str) -> list[str]:
    return [
        "aws", "eks", "describe-nodegroup",
        "--cluster-name", cluster_name,
        "--nodegroup-name", nodegroup_name,
        "--region", region,
        "--query", "nodegroup.scalingConfig.desiredSize",
        "--output", "text",
    ]


def update_nodegroup_scaling_args(
    region: str,
    cluster_name: str,
    nodegroup_name: str,
    min_size: int,
    max_size: int,
    desired_size: int,
) -> list[str]:
    return [
        "aws", "eks", "update-nodegroup-config",
        "--cluster-name", cluster_name,
        "--nodegroup-name", nodegroup_name,
        "--scaling-config", f"minSize={min_size},maxSize={max_size},desiredSize={desired_size}",
        "--region", region,
    ]


def wait_nodegroup_active_args(region: str, cluster_name: str, nodegroup_name: str) -> list[str]:
    return [
        "aws", "eks", "wait", "nodegroup-active",
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


EBS_CSI_ADDON = "aws-ebs-csi-driver"
EBS_CSI_POLICY_ARN = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"


def describe_addon_args(region: str, cluster_name: str, addon_name: str = EBS_CSI_ADDON) -> list[str]:
    return [
        "aws", "eks", "describe-addon",
        "--cluster-name", cluster_name,
        "--addon-name", addon_name,
        "--region", region,
        "--query", "addon.status",
        "--output", "text",
    ]


def create_addon_args(region: str, cluster_name: str, addon_name: str = EBS_CSI_ADDON) -> list[str]:
    return [
        "aws", "eks", "create-addon",
        "--cluster-name", cluster_name,
        "--addon-name", addon_name,
        "--region", region,
        "--resolve-conflicts", "OVERWRITE",
    ]


def wait_addon_active_args(region: str, cluster_name: str, addon_name: str = EBS_CSI_ADDON) -> list[str]:
    return [
        "aws", "eks", "wait", "addon-active",
        "--cluster-name", cluster_name,
        "--addon-name", addon_name,
        "--region", region,
    ]


def attach_role_policy_args(role_name: str, policy_arn: str) -> list[str]:
    return [
        "aws", "iam", "attach-role-policy",
        "--role-name", role_name,
        "--policy-arn", policy_arn,
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
