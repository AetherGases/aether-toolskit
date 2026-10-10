import os
import time
from pathlib import Path

from aether_env.awscli import (
    aws_process_env,
    caller_identity_args,
    cluster_config,
    create_cluster_args,
    delete_security_group_args,
    delete_stack_args,
    describe_stack_args,
    describe_stack_events_args,
    disable_stack_protection_args,
    list_delete_failed_resource_ids_args,
    list_eksctl_stack_names_args,
    list_eks_cluster_security_group_ids_args,
    list_eks_cluster_security_group_ids_by_name_args,
    list_vpc_lattice_resource_ids_args,
    stack_vpc_physical_id_args,
    wait_stack_delete_args,
    create_ecr_args,
    delete_cluster_args,
    delete_nodegroup_args,
    list_nodegroups_args,
    update_nodegroup_scaling_args,
    wait_cluster_deleted_args,
    wait_nodegroup_active_args,
    wait_nodegroup_deleted_args,
    describe_cluster_args,
    describe_ecr_args,
    describe_nodegroup_desired_size_args,
    docker_login_args,
    ecr_password_args,
    ecr_repository,
    image_uri,
    kubeconfig_args,
)
from aether_env.catalog import WORKLOADS, get_workload
from aether_env.config import SecretConfigError, Settings, application_secret_data
from aether_env.confirm import phrase_accepted
from aether_env.images import docker_build_args, docker_push_args, dockerfile_for, rev_parse_args, sync_main_commands
from aether_env.kong import render_kong_config
from aether_env.kube import (
    INGRESS_NGINX_URL,
    apply_stdin_args,
    apply_url_args,
    delete_pvc_args,
    delete_resource_args,
    get_pods_args,
    ingress_hostname_args,
    logs_follow_args,
    ingress_ip_args,
    ingress_nginx_rollout_status_args,
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

_REMOVABLE_STACK_STATUSES = frozenset({
    "ROLLBACK_COMPLETE",
    "CREATE_FAILED",
    "DELETE_FAILED",
    "UPDATE_ROLLBACK_FAILED",
    "UPDATE_ROLLBACK_COMPLETE",
    "ROLLBACK_FAILED",
})

_REUSABLE_STACK_STATUSES = frozenset({
    "CREATE_COMPLETE",
    "UPDATE_COMPLETE",
    "UPDATE_ROLLBACK_COMPLETE",
    "CREATE_IN_PROGRESS",
    "UPDATE_IN_PROGRESS",
    "DELETE_IN_PROGRESS",
})


class Actions:
    def __init__(self, settings: Settings, runner, root: Path, write) -> None:
        self.settings = settings
        self.runner = runner
        self.root = root
        self.write = write

    def subir_ambiente(self, cluster_name: str) -> int:
        status = self._status(cluster_name)
        if status == "ACTIVE":
            scaled = self._scale_nodegroups(cluster_name, self.settings.node_count)
            if scaled != 0:
                return scaled
            self.write("Cluster already exists.")
            return 0
        if status in (None, "CREATING", "PENDING"):
            return self._bootstrap_cluster(cluster_name)
        self.write(f"Cluster status is {status}.")
        return 1

    def derrubar_ambiente(self, cluster_name: str, typed: str) -> int:
        if not phrase_accepted(cluster_name, typed):
            self.write("Confirmation rejected.")
            return 1
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
        if not self._delete_environment_stacks(cluster_name):
            failed = True
        if failed:
            return 1
        return 0

    def subir_workload(self, cluster_name: str, key: str) -> int:
        if not self._require_active(cluster_name):
            return 1
        if self._ensure_kubeconfig(cluster_name) != 0:
            return 1
        if self._ensure_platform(cluster_name) != 0:
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
            if not self._apply_checked(kubeconfig, render_app(workload, image)):
                return 1
        else:
            self._retire_database_claim(str(kubeconfig), key)
            if not self._apply_checked(kubeconfig, render_database(workload)):
                return 1
        scaled = self._run(scale_args(str(kubeconfig), workload.k8s_kind, key, 1))
        if scaled.returncode != 0:
            self._write_output(scaled)
            return scaled.returncode
        if workload.key == "kong" and self._ensure_gateway(cluster_name) != 0:
            return 1
        pods = self._run(get_pods_args(str(kubeconfig)))
        if pods.stdout:
            self.write(pods.stdout)
        return 0

    def escalar_ambiente_zero(self, cluster_name: str) -> int:
        if not self._require_active(cluster_name):
            return 1
        if self._ensure_kubeconfig(cluster_name) != 0:
            return 1
        kubeconfig = str(self._kubeconfig(cluster_name))
        failed = not self._scale_catalog(kubeconfig, 0)
        if self._scale_nodegroups(cluster_name, 0) != 0:
            failed = True
        if failed:
            return 1
        self.write("Scaled to zero. Cluster is still running.")
        return 0

    def escalar_ambiente_um(self, cluster_name: str) -> int:
        if not self._require_active(cluster_name):
            return 1
        if self._ensure_kubeconfig(cluster_name) != 0:
            return 1
        if self._scale_nodegroups(cluster_name, self.settings.node_count) != 0:
            return 1
        kubeconfig = str(self._kubeconfig(cluster_name))
        if not self._scale_catalog(kubeconfig, 1):
            return 1
        self.write("Scaled to one.")
        return 0

    def escalar_workload_zero(self, cluster_name: str, key: str) -> int:
        return self.derrubar_workload(cluster_name, key)

    def escalar_workload_um(self, cluster_name: str, key: str) -> int:
        if not self._require_active(cluster_name):
            return 1
        if self._ensure_kubeconfig(cluster_name) != 0:
            return 1
        if self._scale_nodegroups(cluster_name, self.settings.node_count) != 0:
            return 1
        workload = get_workload(key)
        result = self._run(
            scale_args(str(self._kubeconfig(cluster_name)), workload.k8s_kind, key, 1)
        )
        if result.returncode != 0:
            self._write_output(result)
            return result.returncode
        return 0

    def ver_status(self, cluster_name: str) -> int:
        if not self._require_active(cluster_name):
            return 1
        if self._ensure_kubeconfig(cluster_name, quiet=True) != 0:
            return 1
        result = self._run(get_pods_args(str(self._kubeconfig(cluster_name))))
        self._write_output(result)
        return result.returncode

    def ver_logs(self, cluster_name: str, key: str | None) -> int:
        if not self._require_active(cluster_name):
            return 1
        if self._ensure_kubeconfig(cluster_name, quiet=True) != 0:
            return 1
        selector = f"app={key}" if key else None
        self.write("Following logs. Ctrl+C returns to the menu.")
        try:
            result = self._run(
                logs_follow_args(str(self._kubeconfig(cluster_name)), selector),
                stream=True,
            )
        except KeyboardInterrupt:
            self.write("")
            return 0
        if result.returncode in (0, 130):
            return 0
        self._write_output(result)
        return result.returncode

    def derrubar_workload(self, cluster_name: str, key: str) -> int:
        if not self._require_active(cluster_name):
            return 1
        if self._ensure_kubeconfig(cluster_name) != 0:
            return 1
        workload = get_workload(key)
        result = self._run(scale_args(str(self._kubeconfig(cluster_name)), workload.k8s_kind, key, 0))
        return result.returncode

    def update_workload(self, cluster_name: str, key: str) -> int:
        if not self._require_active(cluster_name):
            return 1
        if self._ensure_kubeconfig(cluster_name) != 0:
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

    def _desired_node_size(self, cluster_name: str, nodegroup_name: str) -> int | None:
        result = self._run(
            describe_nodegroup_desired_size_args(self.settings.aws_region, cluster_name, nodegroup_name)
        )
        if result.returncode != 0:
            return None
        text = result.stdout.strip()
        try:
            return int(text)
        except ValueError:
            return None

    def _scale_catalog(self, kubeconfig: str, replicas: int) -> bool:
        failed = False
        for workload in WORKLOADS:
            result = self._run(scale_args(kubeconfig, workload.k8s_kind, workload.key, replicas))
            if result.returncode != 0:
                text = f"{result.stdout}\n{result.stderr}".lower()
                if "not found" not in text:
                    self._write_output(result)
                    failed = True
        return not failed

    def _scale_nodegroups(self, cluster_name: str, desired: int) -> int:
        names = self._nodegroup_names(cluster_name) or ["ng"]
        max_size = max(self.settings.node_count, 1)
        min_size = 0 if desired == 0 else desired
        failed = False
        for name in names:
            current = self._desired_node_size(cluster_name, name)
            if current == desired:
                continue
            self.write(f"Scaling nodegroup {name} to {desired}.")
            updated = self._run(
                update_nodegroup_scaling_args(
                    self.settings.aws_region,
                    cluster_name,
                    name,
                    min_size,
                    max_size,
                    desired,
                )
            )
            if updated.returncode != 0:
                self._write_output(updated)
                failed = True
                continue
            waited = self._run(
                wait_nodegroup_active_args(self.settings.aws_region, cluster_name, name)
            )
            if waited.returncode != 0:
                self._write_output(waited)
                failed = True
        return 1 if failed else 0

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

    def _cluster_stack_name(self, cluster_name: str) -> str:
        return f"eksctl-{cluster_name}-cluster"

    def _bootstrap_cluster(self, cluster_name: str) -> int:
        status = self._status(cluster_name)
        if status == "ACTIVE":
            return 0
        if status in ("CREATING", "PENDING"):
            if self._wait_cluster_active(cluster_name):
                return 0
            self.write("EKS cluster did not become ACTIVE.")
            return 1
        if status is not None:
            self.write(f"Cluster status is {status}.")
            return 1

        cluster_stack = self._cluster_stack_name(cluster_name)
        stack_status = self._stack_status(cluster_stack)
        if stack_status is not None:
            self.write(
                f"CloudFormation stack {cluster_stack} exists ({stack_status}) "
                f"but EKS cluster {cluster_name} was not found."
            )
            if not self._reconcile_cluster_stack(cluster_name, cluster_stack, stack_status):
                return 1
            if self._status(cluster_name) == "ACTIVE":
                return 0
            stack_status = self._stack_status(cluster_stack)

        if self._status(cluster_name) == "ACTIVE":
            return 0

        if stack_status is None:
            if not self._remove_failed_stack(cluster_name):
                return 1
            if self._stack_status(cluster_stack) is not None:
                self.write(
                    f"Cannot create the cluster while stack {cluster_stack} still exists."
                )
                return 1
            return self._create_cluster_with_eksctl(cluster_name)

        self.write("Ensuring the EKS cluster exists on the current infrastructure.")
        return self._create_cluster_with_eksctl(cluster_name)

    def _create_cluster_with_eksctl(self, cluster_name: str) -> int:
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
        if not self._wait_cluster_active(cluster_name):
            self.write("EKS cluster did not become ACTIVE.")
            return 1
        return 0

    def _reconcile_cluster_stack(
        self,
        _cluster_name: str,
        cluster_stack: str,
        stack_status: str,
    ) -> bool:
        self.write(
            f"Reconciling {cluster_stack} ({stack_status}) for environment start."
        )
        if stack_status == "DELETE_FAILED":
            self.write("Repairing blocked stack deletion (security groups, then retry).")
            self._retry_stack_delete(cluster_stack)
            if not self._wait_stack_absent(cluster_stack):
                self._write_stack_failure_hint(cluster_stack)
                return False
            return True
        if stack_status == "DELETE_IN_PROGRESS":
            if not self._wait_stack_absent(cluster_stack):
                self._write_stack_failure_hint(cluster_stack)
                return False
            return True
        if stack_status in _REMOVABLE_STACK_STATUSES:
            self.write(f"Repairing failed stack {cluster_stack}.")
            if not self._force_delete_stack(
                cluster_stack,
                allow_complete=False,
                wait_for_completion=False,
            ):
                return False
            if not self._wait_stack_absent(cluster_stack):
                self._write_stack_failure_hint(cluster_stack)
                return False
            return True
        if stack_status in (
            "CREATE_COMPLETE",
            "UPDATE_COMPLETE",
            "UPDATE_ROLLBACK_COMPLETE",
        ):
            self.write("Reusing the existing infrastructure stack.")
            return True
        if stack_status in ("CREATE_IN_PROGRESS", "UPDATE_IN_PROGRESS"):
            self.write("Waiting for the infrastructure stack to finish provisioning.")
            return self._wait_stack_status(
                cluster_stack,
                {
                    "CREATE_COMPLETE",
                    "UPDATE_COMPLETE",
                    "UPDATE_ROLLBACK_COMPLETE",
                },
            )
        self.write(f"Stack {cluster_stack} is in state {stack_status}.")
        self._write_stack_failure_hint(cluster_stack)
        return False

    def _wait_stack_status(
        self,
        stack_name: str,
        ok_statuses: set[str],
        timeout: int = 900,
    ) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            status = self._stack_status(stack_name)
            if status in ok_statuses:
                return True
            if status is None:
                return False
            time.sleep(15)
        return False

    def _wait_stack_absent(self, stack_name: str, timeout: int = 600) -> bool:
        self.write(
            f"Waiting for stack {stack_name} to finish deleting "
            f"(up to {timeout // 60} minutes). "
            "This is normal after teardown; orphaned security groups are removed automatically."
        )
        deadline = time.monotonic() + timeout
        last_status: str | None = None
        last_remediation = 0.0
        while time.monotonic() < deadline:
            status = self._stack_status(stack_name)
            if status is None:
                return True
            if status != last_status:
                self.write(f"Stack {stack_name} status: {status}.")
                last_status = status
                last_remediation = 0.0
            if status == "DELETE_FAILED":
                self._retry_stack_delete(stack_name)
            elif status == "DELETE_IN_PROGRESS":
                if time.monotonic() - last_remediation >= 60:
                    self._remediate_stuck_stack_delete(stack_name)
                    last_remediation = time.monotonic()
            time.sleep(15)
        if self._stack_status(stack_name) is None:
            return True
        self._retry_stack_delete(stack_name)
        return self._stack_status(stack_name) is None

    def _remediate_stuck_stack_delete(self, stack_name: str) -> None:
        self.write("Checking for orphaned EKS security groups that block VPC deletion.")
        removed = self._cleanup_orphaned_eks_cluster_security_groups(stack_name)
        if removed:
            self.write(
                f"Removed {removed} orphaned security group(s); "
                "CloudFormation should resume deleting the stack."
            )
        else:
            self.write("No orphaned eks-cluster security groups found.")
        if self._stack_status(stack_name) == "DELETE_FAILED":
            self._retry_stack_delete(stack_name)

    def _retry_stack_delete(self, stack_name: str) -> None:
        self._cleanup_orphaned_eks_cluster_security_groups(stack_name)
        retain_ids = self._delete_failed_resource_ids(stack_name)
        if retain_ids:
            self.write(
                "Retrying stack delete while retaining blocked resources: "
                + ", ".join(retain_ids)
                + "."
            )
            self._delete_stack_and_wait(
                self.settings.aws_region,
                stack_name,
                retain_ids,
                wait=False,
            )
            return
        self._force_delete_stack(
            stack_name,
            allow_complete=True,
            wait_for_completion=False,
        )

    def _wait_cluster_active(self, cluster_name: str, timeout: int = 900) -> bool:
        self.write(
            f"Waiting for cluster {cluster_name} to become ACTIVE "
            f"(up to {timeout // 60} minutes)."
        )
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            status = self._status(cluster_name)
            if status == "ACTIVE":
                return True
            if status not in (None, "CREATING", "PENDING"):
                self.write(f"Cluster status is {status}.")
                return False
            time.sleep(15)
        return False

    def _delete_environment_stacks(self, cluster_name: str) -> bool:
        stacks = self._eksctl_stack_names(cluster_name)
        if not stacks:
            self.write("No CloudFormation stacks left for this environment.")
            return True
        ok = True
        for stack_name in stacks:
            if not self._force_delete_stack(
                stack_name,
                allow_complete=True,
                wait_for_completion=True,
            ):
                ok = False
        return ok

    def _remove_failed_stack(self, cluster_name: str) -> bool:
        stacks = self._eksctl_stack_names(cluster_name)
        if not stacks:
            return True
        ok = True
        for stack_name in stacks:
            status = self._stack_status(stack_name)
            if status is None or status in _REUSABLE_STACK_STATUSES:
                continue
            if status not in _REMOVABLE_STACK_STATUSES:
                continue
            if not self._force_delete_stack(
                stack_name,
                allow_complete=False,
                wait_for_completion=False,
            ):
                ok = False
        return ok

    def _eksctl_stack_names(self, cluster_name: str) -> list[str]:
        listed = self._run(list_eksctl_stack_names_args(self.settings.aws_region, cluster_name))
        names = []
        if listed.returncode == 0:
            text = listed.stdout.strip()
            if text and text not in {"None", "null"}:
                names.extend(part for part in text.split() if part)
        if names:
            return self._sort_eksctl_stacks(names)
        fallback = [
            f"eksctl-{cluster_name}-nodegroup-{name}"
            for name in self._nodegroup_names(cluster_name)
        ]
        fallback.append(f"eksctl-{cluster_name}-cluster")
        present = []
        for stack_name in fallback:
            if self._stack_status(stack_name):
                present.append(stack_name)
        return self._sort_eksctl_stacks(present)

    def _sort_eksctl_stacks(self, stack_names: list[str]) -> list[str]:
        def sort_key(name: str) -> tuple[int, str]:
            if "-nodegroup-" in name:
                return (0, name)
            if name.endswith("-cluster"):
                return (2, name)
            return (1, name)

        return sorted(set(stack_names), key=sort_key)

    def _stack_status(self, stack_name: str) -> str | None:
        described = self._run(describe_stack_args(self.settings.aws_region, stack_name))
        if described.returncode != 0:
            return None
        status = described.stdout.strip()
        if not status or status in {"None", "null"}:
            return None
        return status

    def _force_delete_stack(
        self,
        stack_name: str,
        *,
        allow_complete: bool = False,
        wait_for_completion: bool = True,
    ) -> bool:
        status = self._stack_status(stack_name)
        if status is None:
            return True
        region = self.settings.aws_region
        if status == "DELETE_IN_PROGRESS":
            if wait_for_completion:
                self.write(f"Waiting for stack {stack_name} deletion.")
                if self._run(wait_stack_delete_args(region, stack_name)).returncode == 0:
                    return True
                status = self._stack_status(stack_name)
                if status is None:
                    return True
            else:
                return True
        removable = set(_REMOVABLE_STACK_STATUSES)
        if allow_complete:
            removable.update({
                "CREATE_COMPLETE",
                "UPDATE_COMPLETE",
                "UPDATE_ROLLBACK_COMPLETE",
            })
        if status not in removable:
            self.write(f"CloudFormation stack {stack_name} is {status}.")
            self._write_stack_failure_hint(stack_name)
            return False
        if status == "DELETE_FAILED":
            self.write(f"Retrying cleanup of stuck stack {stack_name}.")
        else:
            self.write(f"Removing stack {stack_name}.")
        if self._run(disable_stack_protection_args(region, stack_name)).returncode != 0:
            return False
        self._cleanup_orphaned_eks_cluster_security_groups(stack_name)
        if self._delete_stack_and_wait(region, stack_name, wait=wait_for_completion):
            return True
        self._cleanup_orphaned_eks_cluster_security_groups(stack_name)
        retain_ids = self._delete_failed_resource_ids(stack_name)
        if retain_ids:
            self.write(
                "Retrying stack delete while retaining blocked resources: "
                + ", ".join(retain_ids)
                + "."
            )
            if self._delete_stack_and_wait(
                region, stack_name, retain_ids, wait=wait_for_completion
            ):
                return True
        remaining = self._stack_status(stack_name)
        if remaining is None:
            return True
        if not wait_for_completion:
            self.write(
                f"Stack {stack_name} is still {remaining}; continuing without waiting."
            )
            return True
        self.write(f"CloudFormation stack {stack_name} is {remaining}.")
        self._write_stack_failure_hint(stack_name)
        return False

    def _delete_stack_and_wait(
        self,
        region: str,
        stack_name: str,
        retain_resources: list[str] | None = None,
        *,
        wait: bool = True,
    ) -> bool:
        retain = list(retain_resources or [])
        lattice_ids = self._vpc_lattice_resource_ids(stack_name)
        for logical_id in lattice_ids:
            if logical_id not in retain:
                retain.append(logical_id)
        if lattice_ids:
            self.write(
                "This account cannot delete VPC Lattice; retaining "
                + ", ".join(lattice_ids)
                + " so the stack can finish deleting."
            )
        deleted = self._run(delete_stack_args(region, stack_name, retain))
        if deleted.returncode != 0 and not self._is_missing(deleted):
            self._write_output(deleted)
            return False
        if not wait:
            return True
        return self._run(wait_stack_delete_args(region, stack_name)).returncode == 0

    def _text_tokens(self, result) -> list[str]:
        if result.returncode != 0:
            return []
        text = result.stdout.strip()
        if not text or text in {"None", "null"}:
            return []
        return [part for part in text.split() if part]

    def _vpc_lattice_resource_ids(self, stack_name: str) -> list[str]:
        return self._text_tokens(
            self._run(list_vpc_lattice_resource_ids_args(self.settings.aws_region, stack_name))
        )

    def _delete_failed_resource_ids(self, stack_name: str) -> list[str]:
        lattice = set(self._vpc_lattice_resource_ids(stack_name))
        failed = self._text_tokens(
            self._run(list_delete_failed_resource_ids_args(self.settings.aws_region, stack_name))
        )
        return sorted(lattice.union(failed))

    def _cluster_name_from_stack(self, stack_name: str) -> str | None:
        prefix = "eksctl-"
        suffix = "-cluster"
        if stack_name.startswith(prefix) and stack_name.endswith(suffix):
            return stack_name[len(prefix):-len(suffix)]
        return None

    def _cleanup_orphaned_eks_cluster_security_groups(self, stack_name: str) -> int:
        cluster_name = self._cluster_name_from_stack(stack_name)
        if cluster_name is None:
            return 0
        if self._status(cluster_name) is not None:
            return 0
        region = self.settings.aws_region
        group_ids: list[str] = []
        vpc_ids = self._text_tokens(
            self._run(stack_vpc_physical_id_args(self.settings.aws_region, stack_name))
        )
        for vpc_id in vpc_ids:
            group_ids.extend(
                self._text_tokens(
                    self._run(
                        list_eks_cluster_security_group_ids_args(
                            region, vpc_id, cluster_name
                        )
                    )
                )
            )
        if not group_ids:
            group_ids = self._text_tokens(
                self._run(
                    list_eks_cluster_security_group_ids_by_name_args(region, cluster_name)
                )
            )
        removed = 0
        for group_id in dict.fromkeys(group_ids):
            self.write(f"Removing orphaned EKS security group {group_id}.")
            deleted = self._run(delete_security_group_args(region, group_id))
            if deleted.returncode == 0 or self._is_missing(deleted):
                removed += 1
            elif deleted.returncode != 0:
                self._write_output(deleted)
        return removed

    def _write_stack_failure_hint(self, stack_name: str) -> None:
        events = self._run(describe_stack_events_args(self.settings.aws_region, stack_name))
        if events.returncode != 0:
            return
        text = events.stdout.strip()
        if text:
            self.write("Recent stack events:")
            self.write(text)

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

    def _publish_image(self, cluster_name: str, workload, account: str, api_url: str, *, stream: bool = True) -> int:
        repository = ecr_repository(theme_for(cluster_name).slug, workload.key)
        described = self._run(describe_ecr_args(self.settings.aws_region, repository))
        if described.returncode != 0:
            created = self._run(create_ecr_args(self.settings.aws_region, repository))
            if created.returncode != 0:
                return created.returncode
        branch = theme_for(cluster_name).branch
        if workload.repo is None:
            dest = self.root / "dockerfiles" / workload.key
            if workload.key == "kong":
                (dest / "kong.yml").write_text(render_kong_config(), encoding="utf-8")
            sha = "local"
        else:
            dest = self.root / "resources" / "build" / cluster_name / workload.repo
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
            if result.stderr:
                self.write(result.stderr)
            return False
        self._write_output(result)
        return False

    def _retire_database_claim(self, kubeconfig: str, key: str) -> None:
        self._run(delete_resource_args(kubeconfig, f"statefulset/{key}"))
        self._run(delete_pvc_args(kubeconfig, f"data-{key}-0"))

    def _ensure_kubeconfig(self, cluster_name: str, *, quiet: bool = False) -> int:
        kubeconfig = self._kubeconfig(cluster_name)
        kubeconfig.parent.mkdir(parents=True, exist_ok=True)
        if not quiet:
            self.write("Updating kubeconfig.")
        result = self._run(kubeconfig_args(self.settings.aws_region, cluster_name, str(kubeconfig)))
        if result.returncode != 0:
            self._write_output(result)
            return 1
        return 0

    def _ensure_platform(self, cluster_name: str) -> int:
        kubeconfig = self._kubeconfig(cluster_name)
        self.write("Applying namespace, secrets, and init data.")
        if not self._apply_checked(kubeconfig, render_namespace()):
            return 1
        try:
            secret_manifest = render_secret(application_secret_data(self.settings))
        except SecretConfigError as exc:
            self.write(str(exc))
            return 1
        if not self._apply_checked(kubeconfig, secret_manifest):
            return 1
        postgres_init = self._read_dir(self.root / "init-postgres")
        if not self._apply_checked(kubeconfig, render_configmap("postgres-init", postgres_init)):
            return 1
        mongo_path = self.root / "init-mongo" / "init.js"
        mongo = mongo_path.read_text(encoding="utf-8") if mongo_path.exists() else ""
        if not self._apply_checked(kubeconfig, render_configmap("mongo-init", {"init.js": mongo})):
            return 1
        return 0

    def _ensure_gateway(self, cluster_name: str) -> int:
        kubeconfig = self._kubeconfig(cluster_name)
        self.write("Installing ingress-nginx.")
        nginx = self._run(apply_url_args(str(kubeconfig), INGRESS_NGINX_URL))
        if nginx.returncode != 0:
            self._write_output(nginx)
            return 1
        self.write("Waiting for ingress-nginx admission webhook (up to 5 minutes).")
        ready = self._run(ingress_nginx_rollout_status_args(str(kubeconfig)))
        if ready.returncode != 0:
            self._write_output(ready)
            self.write("ingress-nginx is not ready; cannot create the gateway Ingress.")
            return 1
        if not self._apply_checked(kubeconfig, render_ingress([get_workload("kong")])):
            return 1
        self.write("Waiting for the load balancer hostname (up to 5 minutes).")
        address = self._wait_address(kubeconfig)
        self._write_gateway_url(cluster_name, f"http://{address}" if address else "")
        return 0

    def _write_gateway_url(self, cluster_name: str, api_url: str) -> None:
        if api_url:
            self.write(f"URL externa ({cluster_name}): {api_url}")
            return
        self.write(
            f"URL externa ({cluster_name}): indisponivel. "
            "Apenas o Kong e publico quando o balanceador estiver pronto."
        )

    def _read_dir(self, directory: Path) -> dict[str, str]:
        files = {}
        if not directory.is_dir():
            return files
        for path in sorted(directory.glob("*.sql")):
            files[path.name] = path.read_text(encoding="utf-8")
        return files

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

    def _kubeconfig(self, cluster_name: str) -> Path:
        return self.root / ".kube" / cluster_name

    def _run(self, args, *, stream=False, stdin=None):
        return self.runner.run(
            args,
            env=aws_process_env(self.settings, os.environ),
            stdin=stdin,
            stream=stream,
        )
