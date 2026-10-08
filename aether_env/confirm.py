from aether_env.theme import PROD, QA


def required_phrase(cluster_name: str) -> str:
    if cluster_name == QA.cluster_name:
        return "yes"
    if cluster_name == PROD.cluster_name:
        return PROD.cluster_name
    raise KeyError(cluster_name)


def phrase_accepted(cluster_name: str, typed: str) -> bool:
    return typed.strip() == required_phrase(cluster_name)
