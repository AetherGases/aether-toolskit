import json
from collections.abc import Mapping, Sequence

from aether_env.catalog import Workload

ENV_FINGERPRINT_ANNOTATION = "aether.toolskit/env-fingerprint"


def _env_annotation_block(fingerprint: str) -> str:
    return f"""      annotations:
        {ENV_FINGERPRINT_ANNOTATION}: "{fingerprint}"
"""


def render_namespace() -> str:
    return "apiVersion: v1\nkind: Namespace\nmetadata:\n  name: aether\n"


def render_secret(data: Mapping[str, str]) -> str:
    lines = [
        "apiVersion: v1",
        "kind: Secret",
        "metadata:",
        "  name: aether-env",
        "  namespace: aether",
        "type: Opaque",
        "stringData:",
    ]
    for key, value in sorted(data.items()):
        lines.append(f"  {key}: {json.dumps(str(value), ensure_ascii=False)}")
    return "\n".join(lines) + "\n"


def render_configmap(name: str, files: Mapping[str, str]) -> str:
    lines = [
        "apiVersion: v1",
        "kind: ConfigMap",
        "metadata:",
        f"  name: {name}",
        "  namespace: aether",
        "data:",
    ]
    for filename, content in files.items():
        lines.append(f"  {filename}: |")
        for line in content.replace("\r\n", "\n").split("\n"):
            lines.append(f"    {line}")
    return "\n".join(lines) + "\n"


def _service(name: str, port: int) -> str:
    return f"""apiVersion: v1
kind: Service
metadata:
  name: {name}
  namespace: aether
spec:
  type: ClusterIP
  selector:
    app: {name}
  ports:
    - port: {port}
      targetPort: {port}
"""


def _probe(port: int) -> str:
    return f"""          readinessProbe:
            tcpSocket:
              port: {port}
            initialDelaySeconds: 5
            periodSeconds: 5
"""


def render_app(workload: Workload, image: str, env_fingerprint: str) -> str:
    ports = ""
    probe = ""
    if workload.container_port:
        ports = f"""          ports:
            - containerPort: {workload.container_port}
"""
        probe = _probe(workload.container_port)
    body = f"""apiVersion: apps/v1
kind: Deployment
metadata:
  name: {workload.key}
  namespace: aether
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: {workload.key}
  template:
    metadata:
      labels:
        app: {workload.key}
{_env_annotation_block(env_fingerprint)}    spec:
      containers:
        - name: {workload.key}
          image: {image}
          imagePullPolicy: Always
{ports}          envFrom:
            - secretRef:
                name: aether-env
{probe}---
"""
    if workload.container_port:
        body += _service(workload.key, workload.container_port)
    return body


def render_ingress(workloads: Sequence[Workload]) -> str:
    gateway = next((w for w in workloads if w.key == "kong"), None)
    if gateway is None:
        return ""
    port = gateway.container_port or 8000
    return f"""apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aether-gateway
  namespace: aether
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {gateway.key}
                port:
                  number: {port}
"""
