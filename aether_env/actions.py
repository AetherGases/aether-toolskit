import os
import time
from pathlib import Path

from aether_env.awscli import (
    aws_process_env,
    caller_identity_args,
    cluster_config,
    create_cluster_args,
    delete_stack_args,
    describe_stack_args,
    disable_stack_protection_args,
    wait_stack_delete_args,
    create_ecr_args,
    delete_cluster_args,
    delete_nodegroup_args,
    list_nodegroups_args,
    wait_cluster_deleted_args,
    wait_nodegroup_deleted_args,
    delete_ecr_args,
    describe_cluster_args,
    describe_ecr_args,
    docker_login_args,
    ecr_password_args,
    ecr_repository,
    image_uri,
    kubeconfig_args,
)
from aether_env.catalog import WORKLOADS, get_workload
from aether_env.config import Settings, application_secret_data
from aether_env.confirm import phrase_accepted
from aether_env.images import docker_build_args, docker_push_args, dockerfile_for, rev_parse_args, sync_main_commands
from aether_env.kube import (
    INGRESS_NGINX_URL,
    apply_stdin_args,
    apply_url_args,
    get_pods_args,
    ingress_hostname_args,
    ingress_ip_args,
    rollout_restart_args,
    rollout_status_args,
    scale_args,
    set_image_args,
)
from aether_env.manifests import (
    render_app,
    render_configmap,
    render_database,
    render_ingress,
    render_namespace,
    render_secret,
)
from aether_env.theme import theme_for


class Actions:
    def __init__(self, settings: Settings, runner, root: Path, write) -> None:
        self.settings = settings
        self.runner = runner
        self.root = root
        self.write = write

    def subir_ambiente(self, cluster_name: str) -> int:
        status = self._status(cluster_name)
        if status is None:
            if not self._remove_failed_stack(cluster_name):
                return 1
            config_path = None
            if self.settings.cluster_role_arn:
                config_path = self.root / ".kube" / f"{cluster_name}.yaml"
                config_path.parent.mkdir(parents=True, exist_ok=True)
                config_path.write_text(
                    cluster_config(
                        self.settings.aws_region,
                        cluster_name,
                        self.settings.node_type,
                        self.settings.node_count,
                        self.settings.cluster_role_arn,
                        self.settings.node_role_arn,
                    ),
                    encoding="utf-8",
                )
            created = self._run(create_cluster_args(
                self.settings.aws_region,
                cluster_name,
                self.settings.node_type,
                self.settings.node_count,
                str(config_path) if config_path else None,
            ), stream=True)
            if created.returncode != 0:
                self.write("Failed to create the cluster.")
                return 1
        elif status != "ACTIVE":
            self.write(f"Cluster status is {status}.")
            return 1
        else:
            self.write("Cluster already exists. Publishing workloads.")
        kubeconfig = self._kubeconfig(cluster_name)
        kubeconfig.parent.mkdir(parents=True, exist_ok=True)
        if self._run(kubeconfig_args(self.settings.aws_region, cluster_name, str(kubeconfig))).returncode != 0:
            return 1
        account = self._account()
        if account is None:
            return 1
        if self._login(account) != 0:
            return 1
        failures = []
        theme = theme_for(cluster_name)
        slug = theme.slug
        branch = theme.branch
        for workload in WORKLOADS:
            if workload.kind == "app" and workload.key != "aether-web-flow":
                if self._publish_image(cluster_name, workload, account, "") != 0:
                    failures.append(workload.key)
        if not self._apply_checked(kubeconfig, render_namespace()):
            return 1
        if not self._apply_checked(kubeconfig, render_secret(application_secret_data(self.settings))):
            return 1
        if not self._apply_checked(kubeconfig, render_configmap("postgres-init", self._read_dir(self.root / "init-postgres"))):
            return 1
        mongo = (self.root / "init-mongo" / "init.js").read_text(encoding="utf-8")
        if not self._apply_checked(kubeconfig, render_configmap("mongo-init", {"init.js": mongo})):
            return 1
        for workload in WORKLOADS:
            if workload.kind == "database":
                if not self._apply_checked(kubeconfig, render_database(workload)):
                    return 1
            elif workload.kind == "app" and workload.key != "aether-web-flow" and workload.key not in failures:
                image = self._image(account, slug, workload.key, branch)
                if not self._apply_checked(kubeconfig, render_app(workload, image)):
                    return 1
        nginx = self._run(apply_url_args(str(kubeconfig), INGRESS_NGINX_URL))
        if nginx.returncode != 0:
            if nginx.stdout:
                self.write(nginx.stdout)
            if nginx.stderr:
                self.write(nginx.stderr)
            return 1
        if not self._apply_checked(kubeconfig, render_ingress([item for item in WORKLOADS if item.ingress_path])):
            return 1
        address = self._wait_address(kubeconfig)
        if address:
            api_url = f"http://{address}"
        else:
            api_url = ""
            self.write("Load balancer has no hostname. aether-web-flow will keep an empty API_URL.")
        web = get_workload("aether-web-flow")
        if self._publish_image(cluster_name, web, account, api_url) != 0:
            failures.append(web.key)
        else:
            if not self._apply_checked(kubeconfig, render_app(web, self._image(account, slug, web.key, branch))):
                return 1
        pods = self._run(get_pods_args(str(kubeconfig)))
        self.write(pods.stdout)
        if address:
            for workload in WORKLOADS:
                if workload.ingress_path:
                    self.write(f"{api_url}{'' if workload.ingress_path == '/' else workload.ingress_path}")
        if failures:
            self.write("Failed to build " + ", ".join(failures) + ".")
            return 1
        return 0

    def derrubar_ambiente(self, cluster_name: str, typed: str) -> int:
        if not phrase_accepted(cluster_name, typed):
            self.write("Confirmation rejected.")
            return 1
        slug = theme_for(cluster_name).slug
        failed = False
        described = self._run(describe_cluster_args(self.settings.aws_region, cluster_name))
        if described.returncode == 0 or not self._is_missing(described):
            if described.returncode != 0:
                self.write("Could not describe the cluster; attempting delete anyway.")
                self._write_output(described)
            for name in self._nodegroup_names(cluster_name):
                self.write(f"Deleting nodegroup {name}.")
                deleted = self._run(delete_nodegroup_args(self.settings.aws_region, cluster_name, name))
                if deleted.returncode == 0:
                    waited = self._run(
                        wait_nodegroup_deleted_args(self.settings.aws_region, cluster_name, name)
                    )
                    if waited.returncode != 0 and not self._is_missing(waited):
                        self.write(f"Failed to delete nodegroup {name}.")
                        self._write_output(waited)
                        failed = True
                elif not self._is_missing(deleted):
                    self.write(f"Failed to delete nodegroup {name}.")
                    self._write_output(deleted)
                    failed = True
            self.write(f"Deleting cluster {cluster_name}.")
            deleted = self._run(delete_cluster_args(self.settings.aws_region, cluster_name))
            if deleted.returncode == 0:
                waited = self._run(wait_cluster_deleted_args(self.settings.aws_region, cluster_name))
                if waited.returncode != 0 and not self._is_missing(waited):
                    self.write("Failed to delete the cluster.")
                    self._write_output(waited)
                    failed = True
            elif not self._is_missing(deleted):
                self.write("Failed to delete the cluster.")
                self._write_output(deleted)
                failed = True
        else:
            self.write("Cluster was already absent.")
        if not self._delete_leftover_stacks(cluster_name):
            failed = True
        ecr_failed = False
        for workload in WORKLOADS:
            if workload.kind == "app":
                repository = ecr_repository(slug, workload.key)
                deleted = self._run(delete_ecr_args(self.settings.aws_region, repository))
                if deleted.returncode != 0:
                    self.write(f"Failed to delete {repository}.")
                    if deleted.stdout:
                        self.write(deleted.stdout)
                    if deleted.stderr:
                        self.write(deleted.stderr)
                    ecr_failed = True
        kubeconfig = self._kubeconfig(cluster_name)
        if kubeconfig.exists():
            kubeconfig.unlink()
        if ecr_failed or failed:
            return 1
        return 0

    def subir_workload(self, cluster_name: str, key: str) -> int:
        if not self._require_active(cluster_name):
            return 1
        workload = get_workload(key)
        kubeconfig = self._kubeconfig(cluster_name)
        if workload.kind == "app":
            account = self._account()
            if account is None or self._login(account) != 0:
                return 1
            api_url = ""
            if workload.key == "aether-web-flow":
                address = self._wait_address(kubeconfig)
                api_url = f"http://{address}" if address else ""
            if self._publish_image(cluster_name, workload, account, api_url) != 0:
                self.write(f"Failed to build {key}.")
                return 1
            image = self._image(account, theme_for(cluster_name).slug, key, theme_for(cluster_name).branch)
            if self._apply(kubeconfig, render_app(workload, image)).returncode != 0:
                return 1
        else:
            if self._apply(kubeconfig, render_database(workload)).returncode != 0:
                return 1
        scaled = self._run(scale_args(str(kubeconfig), workload.k8s_kind, key, 1))
        return scaled.returncode

    def derrubar_workload(self, cluster_name: str, key: str) -> int:
        if not self._require_active(cluster_name):
            return 1
        workload = get_workload(key)
        result = self._run(scale_args(str(self._kubeconfig(cluster_name)), workload.k8s_kind, key, 0))
        return result.returncode

    def update_workload(self, cluster_name: str, key: str) -> int:
        if not self._require_active(cluster_name):
            return 1
        workload = get_workload(key)
        kubeconfig = str(self._kubeconfig(cluster_name))
        if workload.kind == "database":
            restarted = self._run(rollout_restart_args(kubeconfig, key))
            if restarted.returncode != 0:
                return restarted.returncode
            return self._run(rollout_status_args(kubeconfig, "statefulset", key)).returncode
        account = self._account()
        if account is None or self._login(account) != 0:
            return 1
        api_url = ""
        if workload.key == "aether-web-flow":
            address = self._wait_address(self._kubeconfig(cluster_name))
            api_url = f"http://{address}" if address else ""
        if self._publish_image(cluster_name, workload, account, api_url) != 0:
            self.write(f"Failed to build {key}.")
            return 1
        image = self._image(account, theme_for(cluster_name).slug, key, theme_for(cluster_name).branch)
        updated = self._run(set_image_args(kubeconfig, key, image))
        if updated.returncode != 0:
            return updated.returncode
        return self._run(rollout_status_args(kubeconfig, "deployment", key)).returncode

    def _nodegroup_names(self, cluster_name: str) -> list[str]:
        listed = self._run(list_nodegroups_args(self.settings.aws_region, cluster_name))
        names = []
        if listed.returncode == 0:
            text = listed.stdout.strip()
            if text and text not in {"None", "null"}:
                names.extend(part for part in text.split() if part)
            return names
        return ["ng"]

    def _is_missing(self, result) -> bool:
        text = f"{result.stdout}\n{result.stderr}".lower()
        return "resourcenotfoundexception" in text or "does not exist" in text

    def _write_output(self, result) -> None:
        if result.stdout:
            self.write(result.stdout)
        if result.stderr:
            self.write(result.stderr)

    def _delete_leftover_stacks(self, cluster_name: str) -> bool:
        stacks = [
            f"eksctl-{cluster_name}-nodegroup-{name}"
            for name in self._nodegroup_names(cluster_name)
        ]
        stacks.append(f"eksctl-{cluster_name}-cluster")
        ok = True
        for stack_name in stacks:
            described = self._run(describe_stack_args(self.settings.aws_region, stack_name))
            if described.returncode != 0 or not described.stdout.strip():
                continue
            self.write(f"Removing stack {stack_name}.")
            region = self.settings.aws_region
            if self._run(disable_stack_protection_args(region, stack_name)).returncode != 0:
                ok = False
                continue
            if self._run(delete_stack_args(region, stack_name)).returncode != 0:
                ok = False
                continue
            if self._run(wait_stack_delete_args(region, stack_name)).returncode != 0:
                ok = False
        return ok

    def _remove_failed_stack(self, cluster_name: str) -> bool:
        stack_name = f"eksctl-{cluster_name}-cluster"
        described = self._run(describe_stack_args(self.settings.aws_region, stack_name))
        stack_status = described.stdout.strip()
        if described.returncode != 0 or not stack_status:
            return True
        if stack_status not in {"ROLLBACK_COMPLETE", "CREATE_FAILED"}:
            self.write(f"CloudFormation stack {stack_name} is {stack_status}.")
            return False
        self.write(f"Removing failed stack {stack_name}.")
        region = self.settings.aws_region
        if self._run(disable_stack_protection_args(region, stack_name)).returncode != 0:
            return False
        if self._run(delete_stack_args(region, stack_name)).returncode != 0:
            return False
        return self._run(wait_stack_delete_args(region, stack_name)).returncode == 0

    def _require_active(self, cluster_name: str) -> bool:
        if self._status(cluster_name) == "ACTIVE":
            return True
        self.write("Environment is stopped. Start the environment first.")
        return False

    def _status(self, cluster_name: str) -> str | None:
        result = self._run(describe_cluster_args(self.settings.aws_region, cluster_name))
        if result.returncode != 0:
            return None
        return result.stdout.strip()

    def _account(self) -> str | None:
        result = self._run(caller_identity_args())
        if result.returncode != 0:
            return None
        return result.stdout.strip()

    def _login(self, account: str) -> int:
        password = self._run(ecr_password_args(self.settings.aws_region))
        if password.returncode != 0:
            return password.returncode
        registry = f"{account}.dkr.ecr.{self.settings.aws_region}.amazonaws.com"
        return self._run(docker_login_args(registry), stdin=password.stdout.strip()).returncode

    def _publish_image(self, cluster_name: str, workload, account: str, api_url: str) -> int:
        repository = ecr_repository(theme_for(cluster_name).slug, workload.key)
        described = self._run(describe_ecr_args(self.settings.aws_region, repository))
        if described.returncode != 0:
            created = self._run(create_ecr_args(self.settings.aws_region, repository))
            if created.returncode != 0:
                return created.returncode
        dest = self.root / "resources" / "build" / cluster_name / workload.repo
        branch = theme_for(cluster_name).branch
        for command in sync_main_commands(workload.repo, str(dest), dest.exists(), branch):
            if self._run(command).returncode != 0:
                return 1
        parsed = self._run(rev_parse_args(str(dest)))
        if parsed.returncode != 0:
            return 1
        sha = parsed.stdout.strip()
        if not sha:
            return 1
        tags = [
            self._image(account, theme_for(cluster_name).slug, workload.key, f"{branch}-{sha}"),
            self._image(account, theme_for(cluster_name).slug, workload.key, branch),
        ]
        dockerfile = dockerfile_for(self.root, workload, dest)
        build_args = {"API_URL": api_url} if workload.key == "aether-web-flow" else {}
        built = self._run(docker_build_args(str(dockerfile), str(dest), tags, build_args), stream=True)
        if built.returncode != 0:
            return built.returncode
        for tag in tags:
            if self._run(docker_push_args(tag), stream=True).returncode != 0:
                return 1
        return 0

    def _image(self, account: str, slug: str, key: str, tag: str) -> str:
        return image_uri(account, self.settings.aws_region, ecr_repository(slug, key), tag)

    def _apply(self, kubeconfig: Path, manifest: str):
        return self._run(apply_stdin_args(str(kubeconfig)), stdin=manifest)

    def _apply_checked(self, kubeconfig: Path, manifest: str) -> bool:
        result = self._apply(kubeconfig, manifest)
        if result.returncode == 0:
            return True
        if manifest.startswith("apiVersion: v1\nkind: Secret\n"):
            self.write("Failed to apply Secret aether-env.")
            return False
        if result.stdout:
            self.write(result.stdout)
        if result.stderr:
            self.write(result.stderr)
        return False

    def _wait_address(self, kubeconfig: Path) -> str:
        deadline = time.monotonic() + 300
        while time.monotonic() < deadline:
            host = self._run(ingress_hostname_args(str(kubeconfig))).stdout.strip()
            if host:
                return host
            ip = self._run(ingress_ip_args(str(kubeconfig))).stdout.strip()
            if ip:
                return ip
            time.sleep(5)
        return ""

    def _read_dir(self, directory: Path) -> dict[str, str]:
        files = {}
        for path in sorted(directory.glob("*.sql")):
            files[path.name] = path.read_text(encoding="utf-8")
        return files

    def _kubeconfig(self, cluster_name: str) -> Path:
        return self.root / ".kube" / cluster_name

    def _run(self, args, *, stream=False, stdin=None):
        return self.runner.run(
            args,
            env=aws_process_env(self.settings, os.environ),
            stdin=stdin,
            stream=stream,
        )
