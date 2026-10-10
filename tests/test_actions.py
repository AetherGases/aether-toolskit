import threading
from pathlib import Path
from unittest.mock import patch

from aether_env.actions import Actions
from aether_env.config import load_settings
from aether_env.kube import INGRESS_NGINX_URL
from aether_env.runner import CommandResult


class FakeRunner:
    def __init__(
        self,
        describe_code=0,
        describe_stdout="ACTIVE\n",
        hostname="lb.example.com",
        scripted_fn=None,
    ):
        self.calls = []
        self.describe_code = describe_code
        self.describe_stdout = describe_stdout
        self.hostname = hostname
        self.scripted_fn = scripted_fn
        self._lock = threading.Lock()

    def run(self, args, *, env=None, cwd=None, stdin=None, stream=False):
        tup = tuple(args)
        with self._lock:
            self.calls.append(tup)
        if self.scripted_fn is not None:
            override = self.scripted_fn(tup)
            if override is not None:
                return override
        stdout = ""
        code = 0
        if tup[:3] == ("aws", "eks", "describe-cluster"):
            return CommandResult(tup, self.describe_code, self.describe_stdout, "")
        if tup[:3] == ("aws", "sts", "get-caller-identity"):
            stdout = "123456789012\n"
        elif "rev-parse" in tup:
            stdout = "abc123\n"
        elif tup[:4] == ("aws", "ecr", "get-login-password"):
            stdout = "token\n"
        elif tup[-1].endswith("hostname}"):
            stdout = self.hostname
        return CommandResult(tup, code, stdout, "")


def _settings():
    return load_settings({
        "AWS_ACCESS_KEY_ID": "aki",
        "AWS_SECRET_ACCESS_KEY": "secret",
        "AWS_REGION": "sa-east-1",
        "POSTGRES_USER": "sa",
        "POSTGRES_PASSWORD": "pw",
        "POSTGRES_DB_FIRST_YEAR": "dbAether1Year",
        "POSTGRES_DB_SECOND_YEAR": "dbAether2Year",
        "MONGO_USER": "mongo",
        "MONGO_PASSWORD": "mp",
        "MONGO_DB": "dbAether",
        "REDIS_PASSWORD": "rp",
        "JWT_SECRET": "jwt",
        "OAUTH_ISSUER": "https://aethergases.org/hub",
        "OAUTH_AUDIENCE": "https://aethergases.org/hub/aether-api/v1/mcp/",
    })


def test_teardown_deletes_nodegroup_before_cluster():
    root = Path(__file__).resolve().parents[1]

    def listed_nodegroup(tup):
        if tup[:3] == ("aws", "eks", "list-nodegroups"):
            return CommandResult(tup, 0, "ng\n", "")
        if tup[:3] == ("aws", "cloudformation", "describe-stacks"):
            return CommandResult(tup, 0, "CREATE_COMPLETE\n", "")
        return None

    runner = FakeRunner(scripted_fn=listed_nodegroup)
    actions = Actions(_settings(), runner, root, lambda message: None)
    assert actions.derrubar_ambiente("aether-qa", "yes") == 0
    nodegroup_at = next(i for i, call in enumerate(runner.calls) if call[:3] == ("aws", "eks", "delete-nodegroup"))
    cluster_at = next(i for i, call in enumerate(runner.calls) if call[:3] == ("aws", "eks", "delete-cluster"))
    assert nodegroup_at < cluster_at
    stack_at = next(i for i, call in enumerate(runner.calls) if call[:3] == ("aws", "cloudformation", "delete-stack"))
    assert cluster_at < stack_at
    assert any("eksctl-aether-qa-cluster" in call for call in runner.calls if call[:3] == ("aws", "cloudformation", "delete-stack"))
    assert all(call[:2] != ("eksctl", "delete") for call in runner.calls)
    assert all(call[:3] != ("aws", "ecr", "delete-repository") for call in runner.calls)


def test_teardown_still_deletes_when_describe_is_denied():
    messages = []

    def denied(tup):
        if tup[:3] == ("aws", "eks", "describe-cluster"):
            return CommandResult(tup, 254, "", "AccessDeniedException: voc-cancel-cred")
        if tup[:3] == ("aws", "eks", "list-nodegroups"):
            return CommandResult(tup, 254, "", "AccessDeniedException: voc-cancel-cred")
        return None

    runner = FakeRunner(scripted_fn=denied)
    actions = Actions(_settings(), runner, Path("."), messages.append)
    actions.derrubar_ambiente("aether-qa", "yes")
    joined = "\n".join(messages)
    assert "Cluster was already absent." not in joined
    assert any(call[:3] == ("aws", "eks", "delete-nodegroup") for call in runner.calls)
    assert any(call[:3] == ("aws", "eks", "delete-cluster") for call in runner.calls)


def test_teardown_deletes_leftover_stacks_when_cluster_already_absent():
    root = Path(__file__).resolve().parents[1]
    messages = []

    def absent_cluster_with_stack(tup):
        if tup[:3] == ("aws", "eks", "describe-cluster"):
            return CommandResult(tup, 254, "", "ResourceNotFoundException")
        if tup[:3] == ("aws", "cloudformation", "describe-stacks"):
            return CommandResult(tup, 0, "CREATE_COMPLETE\n", "")
        return None

    runner = FakeRunner(describe_code=254, describe_stdout="", scripted_fn=absent_cluster_with_stack)
    actions = Actions(_settings(), runner, root, messages.append)
    assert actions.derrubar_ambiente("aether-qa", "yes") == 0
    assert "Cluster was already absent." in messages
    assert any(
        call[:3] == ("aws", "cloudformation", "delete-stack") and "eksctl-aether-qa-cluster" in call
        for call in runner.calls
    )
    assert all(call[:3] != ("aws", "ecr", "delete-repository") for call in runner.calls)


def test_wrong_phrase_does_not_delete():
    runner = FakeRunner()
    actions = Actions(_settings(), runner, Path("."), lambda message: None)
    assert actions.derrubar_ambiente("aether-prod", "yes") == 1
    assert all("delete" not in call for call in runner.calls)


def test_follow_logs_for_one_workload_and_all():
    messages = []
    runner = FakeRunner()
    actions = Actions(_settings(), runner, Path("."), messages.append)
    assert actions.ver_logs("aether-qa", "postgres") == 0
    assert "Updating kubeconfig." not in messages
    assert any(
        call[0] == "kubectl" and "logs" in call and "-f" in call and "app=postgres" in call
        for call in runner.calls
    )
    runner.calls.clear()
    assert actions.ver_logs("aether-qa", None) == 0
    assert any(
        call[0] == "kubectl" and "logs" in call and "-f" in call
        and call[call.index("-l") + 1] == "app"
        for call in runner.calls
    )


def test_container_status_prints_pods():
    messages = []

    def pods(tup):
        if tup[0] == "kubectl" and "get" in tup and "pods" in tup:
            return CommandResult(tup, 0, "postgres-0   1/1   Running\n", "")
        return None

    runner = FakeRunner(scripted_fn=pods)
    actions = Actions(_settings(), runner, Path("."), messages.append)
    assert actions.ver_status("aether-qa") == 0
    assert "Updating kubeconfig." not in messages
    assert any("postgres-0" in message for message in messages)
    assert any(call[0] == "kubectl" and "get" in call and "pods" in call for call in runner.calls)


def test_stopped_environment_refuses_logs_and_status():
    messages = []
    runner = FakeRunner(describe_code=254, describe_stdout="")
    actions = Actions(_settings(), runner, Path("."), messages.append)
    assert actions.ver_logs("aether-qa", None) == 1
    assert actions.ver_status("aether-qa") == 1
    assert messages == [
        "Environment is stopped. Start the environment first.",
        "Environment is stopped. Start the environment first.",
    ]
    assert all(call[0] != "kubectl" or "logs" not in call for call in runner.calls)


def test_stopped_environment_refuses_item_action():
    messages = []
    runner = FakeRunner(describe_code=254, describe_stdout="")
    actions = Actions(_settings(), runner, Path("."), messages.append)
    assert actions.subir_workload("aether-qa", "postgres") == 1
    assert messages == ["Environment is stopped. Start the environment first."]
    assert all("scale" not in call for call in runner.calls)


def test_database_update_restarts_and_skips_docker():
    runner = FakeRunner()
    actions = Actions(_settings(), runner, Path("."), lambda message: None)
    assert actions.update_workload("aether-qa", "postgres") == 0
    flat = [" ".join(call) for call in runner.calls]
    assert any(item.startswith("kubectl") and "rollout restart statefulset/postgres" in item for item in flat)
    assert all(not item.startswith("docker build") for item in flat)


def test_active_cluster_skips_eksctl_create_even_with_stack():
    root = Path(__file__).resolve().parents[1]

    def scripted(tup):
        if tup[:3] == ("aws", "eks", "describe-cluster"):
            return CommandResult(tup, 0, "ACTIVE\n", "")
        if tup[:3] == ("aws", "cloudformation", "describe-stacks"):
            return CommandResult(tup, 0, "CREATE_COMPLETE\n", "")
        return None

    runner = FakeRunner(scripted_fn=scripted)
    actions = Actions(_settings(), runner, root, lambda message: None)
    assert actions._bootstrap_cluster("aether-qa") == 0
    assert all(call[:3] != ("eksctl", "create", "cluster") for call in runner.calls)


def test_reconcile_reuses_healthy_stack_and_creates_cluster():
    root = Path(__file__).resolve().parents[1]

    def scripted(tup):
        if tup[:3] == ("aws", "eks", "describe-cluster"):
            return CommandResult(tup, 254, "", "ResourceNotFoundException")
        if tup[:3] == ("aws", "cloudformation", "describe-stacks"):
            return CommandResult(tup, 0, "CREATE_COMPLETE\n", "")
        return None

    messages = []
    runner = FakeRunner(scripted_fn=scripted)
    actions = Actions(_settings(), runner, root, messages.append)
    with patch.object(Actions, "_wait_cluster_active", return_value=True):
        assert actions._bootstrap_cluster("aether-qa") == 0
    assert any(call[:3] == ("eksctl", "create", "cluster") for call in runner.calls)
    assert all(call[:3] != ("aws", "cloudformation", "delete-stack") for call in runner.calls)
    assert any("Reusing the existing infrastructure stack" in message for message in messages)


def test_delete_failed_stack_is_repaired_before_create():
    root = Path(__file__).resolve().parents[1]
    stack_deleted = {"value": False}

    def scripted(tup):
        if tup[:3] == ("aws", "eks", "describe-cluster"):
            return CommandResult(tup, 254, "", "ResourceNotFoundException")
        if tup[:3] == ("aws", "cloudformation", "delete-stack"):
            stack_deleted["value"] = True
            return CommandResult(tup, 0, "", "")
        if tup[:3] == ("aws", "cloudformation", "describe-stacks"):
            if stack_deleted["value"]:
                return CommandResult(tup, 254, "", "does not exist")
            return CommandResult(tup, 0, "DELETE_FAILED\n", "")
        return None

    messages = []
    runner = FakeRunner(scripted_fn=scripted)
    actions = Actions(_settings(), runner, root, messages.append)
    with patch.object(Actions, "_wait_stack_absent", return_value=True), patch.object(
        Actions, "_wait_cluster_active", return_value=True
    ):
        assert actions._bootstrap_cluster("aether-qa") == 0
    assert any(call[:3] == ("eksctl", "create", "cluster") for call in runner.calls)
    assert any(call[:3] == ("aws", "cloudformation", "delete-stack") for call in runner.calls)
    assert any("Repairing blocked stack deletion" in message for message in messages)


def test_start_does_not_wait_on_cloudformation_stack_delete():
    root = Path(__file__).resolve().parents[1]

    def deleting_stack(tup):
        if tup[:3] == ("aws", "cloudformation", "describe-stacks"):
            return CommandResult(tup, 0, "DELETE_IN_PROGRESS\n", "")
        return None

    messages = []
    runner = FakeRunner(describe_code=254, describe_stdout="", scripted_fn=deleting_stack)
    actions = Actions(_settings(), runner, root, messages.append)
    with patch.object(Actions, "_wait_stack_absent", return_value=True), patch.object(
        Actions, "_wait_cluster_active", return_value=True
    ):
        actions.subir_ambiente("aether-qa")
    assert all(call[:4] != ("aws", "cloudformation", "wait", "stack-delete-complete") for call in runner.calls)
    assert any("Reconciling" in message for message in messages)
    assert any(call[:3] == ("eksctl", "create", "cluster") for call in runner.calls)


def test_failed_stack_is_removed_before_create():
    root = Path(__file__).resolve().parents[1]

    def failed_stack(tup):
        if tup[:3] == ("aws", "cloudformation", "describe-stacks"):
            return CommandResult(tup, 0, "ROLLBACK_COMPLETE\n", "")
        return None

    messages = []
    runner = FakeRunner(describe_code=254, describe_stdout="", scripted_fn=failed_stack)
    actions = Actions(_settings(), runner, root, messages.append)
    with patch.object(Actions, "_wait_stack_absent", return_value=True), patch.object(
        Actions, "_wait_cluster_active", return_value=True
    ):
        actions.subir_ambiente("aether-qa")
    assert any(call[:4] == ("aws", "cloudformation", "delete-stack", "--stack-name") for call in runner.calls)
    assert any("Removing stack eksctl-aether-qa-cluster." == message for message in messages)
    create_at = next(i for i, call in enumerate(runner.calls) if call[:3] == ("eksctl", "create", "cluster"))
    delete_at = next(i for i, call in enumerate(runner.calls) if call[:3] == ("aws", "cloudformation", "delete-stack"))
    assert delete_at < create_at


def test_stack_cleanup_deletes_orphaned_eks_security_group():
    root = Path(__file__).resolve().parents[1]

    def orphan_sg(tup):
        if tup[:3] == ("aws", "cloudformation", "describe-stacks"):
            return CommandResult(tup, 0, "DELETE_FAILED\n", "")
        if tup[:3] == ("aws", "cloudformation", "list-stack-resources"):
            if tup[-1].endswith("text") and "VPC" in tup[tup.index("--query") + 1]:
                return CommandResult(tup, 0, "vpc-abc\n", "")
            return CommandResult(tup, 0, "", "")
        if tup[:3] == ("aws", "ec2", "describe-security-groups"):
            return CommandResult(tup, 0, "sg-orphan\n", "")
        return None

    messages = []
    runner = FakeRunner(describe_code=254, describe_stdout="", scripted_fn=orphan_sg)
    actions = Actions(_settings(), runner, root, messages.append)
    with patch.object(Actions, "_wait_stack_absent", return_value=True), patch.object(
        Actions, "_wait_cluster_active", return_value=True
    ):
        actions.subir_ambiente("aether-qa")
    assert any("Removing orphaned EKS security group sg-orphan." in message for message in messages)
    assert any(call[:3] == ("aws", "ec2", "delete-security-group") for call in runner.calls)


def test_delete_failed_stack_retains_vpc_lattice_resources():
    root = Path(__file__).resolve().parents[1]

    def lattice_stack(tup):
        if tup[:3] == ("aws", "cloudformation", "describe-stacks"):
            return CommandResult(tup, 0, "DELETE_FAILED\n", "")
        if tup[:3] == ("aws", "cloudformation", "list-stack-resources") and any(
            "VpcLattice" in part for part in tup
        ):
            return CommandResult(tup, 0, "ServiceNetwork\n", "")
        return None

    messages = []
    runner = FakeRunner(describe_code=254, describe_stdout="", scripted_fn=lattice_stack)
    actions = Actions(_settings(), runner, root, messages.append)
    with patch.object(Actions, "_wait_stack_absent", return_value=True), patch.object(
        Actions, "_wait_cluster_active", return_value=True
    ):
        actions.subir_ambiente("aether-qa")
    joined = "\n".join(messages)
    assert "cannot delete VPC Lattice" in joined
    retain_calls = [
        call for call in runner.calls
        if call[:3] == ("aws", "cloudformation", "delete-stack")
        and "--retain-resources" in call
        and "ServiceNetwork" in call
    ]
    assert retain_calls


def test_delete_failed_stack_is_retried_before_create():
    root = Path(__file__).resolve().parents[1]

    def delete_failed_stack(tup):
        if tup[:3] == ("aws", "cloudformation", "describe-stacks"):
            return CommandResult(tup, 0, "DELETE_FAILED\n", "")
        return None

    messages = []
    runner = FakeRunner(describe_code=254, describe_stdout="", scripted_fn=delete_failed_stack)
    actions = Actions(_settings(), runner, root, messages.append)
    with patch.object(Actions, "_wait_stack_absent", return_value=True), patch.object(
        Actions, "_wait_cluster_active", return_value=True
    ):
        actions.subir_ambiente("aether-qa")
    assert any("Retrying cleanup of stuck stack eksctl-aether-qa-cluster." in message for message in messages)
    assert any(call[:4] == ("aws", "cloudformation", "delete-stack", "--stack-name") for call in runner.calls)


def test_missing_cluster_starts_eksctl():
    root = Path(__file__).resolve().parents[1]
    runner = FakeRunner(describe_code=254, describe_stdout="")
    actions = Actions(_settings(), runner, root, lambda message: None)
    with patch.object(Actions, "_wait_stack_absent", return_value=True), patch.object(
        Actions, "_wait_cluster_active", return_value=True
    ):
        actions.subir_ambiente("aether-qa")
    assert any(call[:3] == ("eksctl", "create", "cluster") for call in runner.calls)


def test_subir_ambiente_creates_only_cluster_when_missing():
    root = Path(__file__).resolve().parents[1]
    runner = FakeRunner(describe_code=254, describe_stdout="")
    actions = Actions(_settings(), runner, root, lambda message: None)
    with patch.object(Actions, "_wait_cluster_active", return_value=True):
        assert actions.subir_ambiente("aether-qa") == 0
    assert any(call[:3] == ("eksctl", "create", "cluster") for call in runner.calls)
    assert all(call[:2] != ("docker", "build") for call in runner.calls)
    assert all(call[:2] != ("docker", "push") for call in runner.calls)
    assert all(call[0] != "kubectl" for call in runner.calls)
    assert all(call[:3] != ("aws", "eks", "update-kubeconfig") for call in runner.calls)
    assert all(call[:3] != ("aws", "ecr", "get-login-password") for call in runner.calls)
    assert all(call[:3] != ("aws", "ecr", "create-repository") for call in runner.calls)


def _nodegroup_script(desired: str):
    def scripted(tup):
        if tup[:3] == ("aws", "eks", "list-nodegroups"):
            return CommandResult(tup, 0, "ng\n", "")
        if tup[:3] == ("aws", "eks", "describe-nodegroup"):
            return CommandResult(tup, 0, f"{desired}\n", "")
        return None
    return scripted


def test_scale_environment_to_zero_keeps_cluster():
    messages = []
    runner = FakeRunner(scripted_fn=_nodegroup_script("1"))
    actions = Actions(_settings(), runner, Path("."), messages.append)
    assert actions.escalar_ambiente_zero("aether-qa") == 0
    assert any(
        call[:3] == ("aws", "eks", "update-nodegroup-config")
        and "desiredSize=0" in " ".join(call)
        for call in runner.calls
    )
    assert any(call[:4] == ("aws", "eks", "wait", "nodegroup-active") for call in runner.calls)
    assert all(call[:3] != ("aws", "eks", "delete-cluster") for call in runner.calls)
    assert all(call[:3] != ("aws", "eks", "delete-nodegroup") for call in runner.calls)
    assert all(call[:3] != ("aws", "cloudformation", "delete-stack") for call in runner.calls)


def test_scale_environment_to_zero_scales_all_workloads():
    runner = FakeRunner(scripted_fn=_nodegroup_script("1"))
    actions = Actions(_settings(), runner, Path("."), lambda message: None)
    assert actions.escalar_ambiente_zero("aether-qa") == 0
    scales = [call for call in runner.calls if call[0] == "kubectl" and "scale" in call]
    assert any("deployment/kong" in call and "--replicas=0" in call for call in scales)
    assert any("statefulset/postgres" in call and "--replicas=0" in call for call in scales)


def test_scale_environment_to_one_restores_nodes_and_workloads():
    runner = FakeRunner(scripted_fn=_nodegroup_script("0"))
    actions = Actions(_settings(), runner, Path("."), lambda message: None)
    assert actions.escalar_ambiente_um("aether-qa") == 0
    assert any(
        call[:3] == ("aws", "eks", "update-nodegroup-config")
        and "desiredSize=1" in " ".join(call)
        for call in runner.calls
    )
    scales = [call for call in runner.calls if call[0] == "kubectl" and "scale" in call]
    assert any("deployment/kong" in call and "--replicas=1" in call for call in scales)
    assert any("statefulset/postgres" in call and "--replicas=1" in call for call in scales)
    node_at = next(i for i, call in enumerate(runner.calls) if call[:3] == ("aws", "eks", "update-nodegroup-config"))
    scale_at = next(i for i, call in enumerate(runner.calls) if call[0] == "kubectl" and "scale" in call)
    assert node_at < scale_at
    assert all(call[:2] != ("docker", "build") for call in runner.calls)


def test_scale_workload_to_one_keeps_cluster():
    runner = FakeRunner(scripted_fn=_nodegroup_script("1"))
    actions = Actions(_settings(), runner, Path("."), lambda message: None)
    assert actions.escalar_workload_um("aether-qa", "postgres") == 0
    assert any(
        "scale" in call and "statefulset/postgres" in call and "--replicas=1" in call
        for call in runner.calls
    )
    assert all(call[:2] != ("docker", "build") for call in runner.calls)
    assert all(call[:3] != ("aws", "eks", "delete-cluster") for call in runner.calls)


def test_scale_workload_to_zero_keeps_cluster():
    runner = FakeRunner()
    actions = Actions(_settings(), runner, Path("."), lambda message: None)
    assert actions.escalar_workload_zero("aether-qa", "postgres") == 0
    assert any(
        "scale" in call and "statefulset/postgres" in call and "--replicas=0" in call
        for call in runner.calls
    )
    assert all(call[:3] != ("aws", "eks", "delete-cluster") for call in runner.calls)


def test_stopped_environment_refuses_scale_to_zero():
    messages = []
    runner = FakeRunner(describe_code=254, describe_stdout="")
    actions = Actions(_settings(), runner, Path("."), messages.append)
    assert actions.escalar_ambiente_zero("aether-qa") == 1
    assert messages == ["Environment is stopped. Start the environment first."]
    assert all(call[:3] != ("aws", "eks", "update-nodegroup-config") for call in runner.calls)


def test_active_start_restores_nodegroup_when_scaled_to_zero():
    runner = FakeRunner(scripted_fn=_nodegroup_script("0"))
    actions = Actions(_settings(), runner, Path("."), lambda message: None)
    assert actions.subir_ambiente("aether-qa") == 0
    assert any(
        call[:3] == ("aws", "eks", "update-nodegroup-config")
        and "desiredSize=1" in " ".join(call)
        for call in runner.calls
    )
    assert all(call[:3] != ("eksctl", "create", "cluster") for call in runner.calls)
    assert all(call[0] != "kubectl" for call in runner.calls)


def test_active_cluster_start_does_not_publish_workloads():
    root = Path(__file__).resolve().parents[1]
    messages = []
    runner = FakeRunner()
    actions = Actions(_settings(), runner, root, messages.append)
    assert actions.subir_ambiente("aether-qa") == 0
    assert "Cluster already exists." in messages
    assert "Publishing workloads." not in "\n".join(messages)
    assert all(call[:3] != ("eksctl", "create", "cluster") for call in runner.calls)
    assert all(call[:2] != ("docker", "build") for call in runner.calls)
    assert all(call[0] != "kubectl" for call in runner.calls)


def test_teardown_does_not_delete_ecr_or_kubeconfig(tmp_path):
    kubeconfig = tmp_path / ".kube" / "aether-qa"
    kubeconfig.parent.mkdir(parents=True)
    kubeconfig.write_text("config", encoding="utf-8")

    def listed_nodegroup(tup):
        if tup[:3] == ("aws", "eks", "list-nodegroups"):
            return CommandResult(tup, 0, "ng\n", "")
        return None

    runner = FakeRunner(scripted_fn=listed_nodegroup)
    actions = Actions(_settings(), runner, tmp_path, lambda message: None)
    assert actions.derrubar_ambiente("aether-qa", "yes") == 0
    assert kubeconfig.exists()
    assert all(call[:3] != ("aws", "ecr", "delete-repository") for call in runner.calls)
    assert any(call[:3] == ("aws", "eks", "delete-nodegroup") for call in runner.calls)
    assert any(call[:3] == ("aws", "eks", "delete-cluster") for call in runner.calls)


def test_database_start_uses_node_disk_not_ebs():
    root = Path(__file__).resolve().parents[1]
    runner = FakeRunner()
    actions = Actions(_settings(), runner, root, lambda message: None)
    assert actions.subir_workload("aether-qa", "postgres") == 0
    assert all(call[:3] != ("aws", "eks", "create-addon") for call in runner.calls)
    assert any(call[0] == "kubectl" and "delete" in call and "statefulset/postgres" in call for call in runner.calls)
    assert any(call[0] == "kubectl" and "delete" in call and "data-postgres-0" in call for call in runner.calls)


def test_subir_workload_prepares_kubeconfig_namespace_and_secret():
    root = Path(__file__).resolve().parents[1]
    runner = FakeRunner()
    actions = Actions(_settings(), runner, root, lambda message: None)
    assert actions.subir_workload("aether-qa", "postgres") == 0
    assert any(call[:3] == ("aws", "eks", "update-kubeconfig") for call in runner.calls)
    assert any(call[0] == "kubectl" and call[-2:] == ("-f", "-") for call in runner.calls)
    assert any("scale" in call and "statefulset/postgres" in call for call in runner.calls)


def test_subir_workload_kong_installs_ingress_and_prints_url():
    root = Path(__file__).resolve().parents[1]
    messages = []
    runner = FakeRunner(hostname="lb.example.com")
    actions = Actions(_settings(), runner, root, messages.append)
    assert actions.subir_workload("aether-qa", "kong") == 0
    assert any(INGRESS_NGINX_URL in call for call in runner.calls)
    assert "URL externa (aether-qa): http://lb.example.com" in messages
