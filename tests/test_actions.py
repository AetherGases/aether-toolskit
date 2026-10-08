from pathlib import Path

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

    def run(self, args, *, env=None, cwd=None, stdin=None, stream=False):
        tup = tuple(args)
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
    assert all(call[:2] != ("eksctl", "delete") for call in runner.calls)
    assert any(
        call[:3] == ("aws", "cloudformation", "delete-stack")
        and any("nodegroup-ng" in part for part in call)
        for call in runner.calls
    )


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


def test_wrong_phrase_does_not_delete():
    runner = FakeRunner()
    actions = Actions(_settings(), runner, Path("."), lambda message: None)
    assert actions.derrubar_ambiente("aether-prod", "yes") == 1
    assert all("delete" not in call for call in runner.calls)


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


def test_failed_stack_is_removed_before_create():
    root = Path(__file__).resolve().parents[1]

    def failed_stack(tup):
        if tup[:3] == ("aws", "cloudformation", "describe-stacks"):
            return CommandResult(tup, 0, "ROLLBACK_COMPLETE\n", "")
        return None

    messages = []
    runner = FakeRunner(describe_code=254, describe_stdout="", scripted_fn=failed_stack)
    actions = Actions(_settings(), runner, root, messages.append)
    actions.subir_ambiente("aether-qa")
    assert any(call[:4] == ("aws", "cloudformation", "delete-stack", "--stack-name") for call in runner.calls)
    assert any("Removing failed stack eksctl-aether-qa-cluster." == message for message in messages)
    create_at = next(i for i, call in enumerate(runner.calls) if call[:3] == ("eksctl", "create", "cluster"))
    delete_at = next(i for i, call in enumerate(runner.calls) if call[:3] == ("aws", "cloudformation", "delete-stack"))
    assert delete_at < create_at


def test_missing_cluster_starts_eksctl():
    root = Path(__file__).resolve().parents[1]
    runner = FakeRunner(describe_code=254, describe_stdout="")
    actions = Actions(_settings(), runner, root, lambda message: None)
    actions.subir_ambiente("aether-qa")
    assert any(call[:3] == ("eksctl", "create", "cluster") for call in runner.calls)


def _kubectl_apply_stdin(tup):
    return tup[0] == "kubectl" and tup[-2:] == ("-f", "-")


def test_failed_kubectl_apply_stops_subir_ambiente():
    root = Path(__file__).resolve().parents[1]

    def fail_namespace_apply(tup):
        if _kubectl_apply_stdin(tup):
            return CommandResult(tup, 1, "bad namespace", "apply error")
        return None

    runner = FakeRunner(scripted_fn=fail_namespace_apply)
    actions = Actions(_settings(), runner, root, lambda message: None)
    assert actions.subir_ambiente("aether-qa") == 1
    assert all(call[:3] != ("eksctl", "delete", "cluster") for call in runner.calls)


def test_failed_ingress_nginx_apply_stops_subir_ambiente():
    root = Path(__file__).resolve().parents[1]

    def fail_ingress_nginx_apply(tup):
        if tup[0] == "kubectl" and tup[-1] == INGRESS_NGINX_URL:
            return CommandResult(tup, 1, "nginx stdout", "nginx stderr")
        return None

    messages = []
    runner = FakeRunner(scripted_fn=fail_ingress_nginx_apply)
    actions = Actions(_settings(), runner, root, messages.append)
    assert actions.subir_ambiente("aether-qa") == 1
    assert "nginx stdout" in messages
    assert "nginx stderr" in messages
    web_flow_builds = [
        call for call in runner.calls
        if call[:2] == ("docker", "build") and any("aether-web-flow" in part for part in call)
    ]
    assert not web_flow_builds
    assert all(call[:3] != ("eksctl", "delete", "cluster") for call in runner.calls)


def test_failed_secret_apply_does_not_print_secret():
    root = Path(__file__).resolve().parents[1]
    applies = {"n": 0}

    def fail_secret_apply(tup):
        if _kubectl_apply_stdin(tup):
            applies["n"] += 1
            if applies["n"] == 2:
                return CommandResult(
                    tup,
                    1,
                    'stringData:\n  POSTGRES_PASSWORD: "pw"\n  JWT_SECRET: "jwt"',
                    "apply error",
                )
        return None

    messages = []
    runner = FakeRunner(scripted_fn=fail_secret_apply)
    actions = Actions(_settings(), runner, root, messages.append)
    assert actions.subir_ambiente("aether-qa") == 1
    joined = "\n".join(messages)
    assert "pw" not in joined
    assert "jwt" not in joined
    assert "POSTGRES_PASSWORD" not in joined
    assert "Failed to apply Secret aether-env." in messages
    assert all(call[:3] != ("eksctl", "delete", "cluster") for call in runner.calls)


def test_failed_rev_parse_skips_image_push():
    root = Path(__file__).resolve().parents[1]

    def fail_rev_parse(tup):
        if "rev-parse" in tup:
            return CommandResult(tup, 1, "", "fatal: not a git repository")
        return None

    runner = FakeRunner(scripted_fn=fail_rev_parse)
    actions = Actions(_settings(), runner, root, lambda message: None)
    assert actions.subir_ambiente("aether-qa") == 1
    assert all(call[:2] != ("docker", "build") for call in runner.calls)
    assert all(call[:2] != ("docker", "push") for call in runner.calls)
    assert all(call[:3] != ("eksctl", "delete", "cluster") for call in runner.calls)


def test_failed_ecr_delete_returns_error(tmp_path):
    kubeconfig = tmp_path / ".kube" / "aether-qa"
    kubeconfig.parent.mkdir(parents=True)
    kubeconfig.write_text("config", encoding="utf-8")

    def fail_ecr_delete(tup):
        if tup[:3] == ("aws", "ecr", "delete-repository"):
            return CommandResult(tup, 1, "ecr stdout", "ecr stderr")
        return None

    messages = []
    runner = FakeRunner(scripted_fn=fail_ecr_delete)
    actions = Actions(_settings(), runner, tmp_path, messages.append)
    assert actions.derrubar_ambiente("aether-qa", "yes") == 1
    assert not kubeconfig.exists()
    assert any("Failed to delete" in message for message in messages)
