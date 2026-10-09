from dataclasses import dataclass


@dataclass(frozen=True)
class Theme:
    cluster_name: str
    slug: str
    branch: str
    accent: str
    text: str
    dim: str
    reset: str


QA = Theme("aether-qa", "qa", "develop", "\033[94m", "\033[97m", "\033[2m", "\033[0m")
PROD = Theme("aether-prod", "prod", "main", "\033[91m", "\033[97m", "\033[2m", "\033[0m")


def theme_for(cluster_name: str) -> Theme:
    if cluster_name == QA.cluster_name:
        return QA
    if cluster_name == PROD.cluster_name:
        return PROD
    raise KeyError(cluster_name)
