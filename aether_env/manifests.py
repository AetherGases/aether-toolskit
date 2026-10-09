import json
from collections.abc import Mapping, Sequence

from aether_env.catalog import Workload


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


def render_database(workload: Workload) -> str:
    if workload.key == "postgres":
        container = """        - name: postgres
          image: postgres:16.10
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: aether-env
                  key: POSTGRES_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: aether-env
                  key: POSTGRES_PASSWORD
            - name: POSTGRES_DB
              valueFrom:
                secretKeyRef:
                  name: aether-env
                  key: POSTGRES_DB_SECOND_YEAR
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
            - name: init
              mountPath: /docker-entrypoint-initdb.d
""" + _probe(5432)
        extra_volume = """      volumes:
        - name: init
          configMap:
            name: postgres-init
"""
    elif workload.key == "mongo":
        container = """        - name: mongo
          image: mongo:8.0.13
          ports:
            - containerPort: 27017
          env:
            - name: MONGO_INITDB_ROOT_USERNAME
              valueFrom:
                secretKeyRef:
                  name: aether-env
                  key: MONGO_USER
            - name: MONGO_INITDB_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: aether-env
                  key: MONGO_PASSWORD
            - name: MONGO_INITDB_DATABASE
              valueFrom:
                secretKeyRef:
                  name: aether-env
                  key: MONGO_DB
          volumeMounts:
            - name: data
              mountPath: /data/db
            - name: init
              mountPath: /docker-entrypoint-initdb.d
""" + _probe(27017)
        extra_volume = """      volumes:
        - name: init
          configMap:
            name: mongo-init
"""
    else:
        container = """        - name: redis
          image: redis:8.2
          command: ["sh", "-c", "redis-server --requirepass \\"$REDIS_PASSWORD\\" --appendonly yes"]
          ports:
            - containerPort: 6379
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: aether-env
                  key: REDIS_PASSWORD
          volumeMounts:
            - name: data
              mountPath: /data
""" + _probe(6379)
        extra_volume = ""
    body = f"""apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {workload.key}
  namespace: aether
spec:
  serviceName: {workload.key}
  replicas: 1
  selector:
    matchLabels:
      app: {workload.key}
  template:
    metadata:
      labels:
        app: {workload.key}
    spec:
      containers:
{container}{extra_volume}  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 20Gi
---
{_service(workload.key, workload.container_port or 0)}"""
    return body


def render_app(workload: Workload, image: str) -> str:
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
  selector:
    matchLabels:
      app: {workload.key}
  template:
    metadata:
      labels:
        app: {workload.key}
    spec:
      containers:
        - name: {workload.key}
          image: {image}
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
