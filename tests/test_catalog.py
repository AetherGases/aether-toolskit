from aether_env.catalog import WORKLOADS, get_workload
from aether_env.confirm import phrase_accepted, required_phrase
from aether_env.theme import PROD, QA


def test_catalog_has_nine_apps():
    keys = [item.key for item in WORKLOADS]
    assert keys == [
        "kong",
        "aether-ms-auth",
        "aether-ms-calculator",
        "aether-ms-inventory",
        "aether-ms-cloudinary",
        "ms-aeko-hub",
        "aether-rpa",
        "aether-web-flow",
        "aether-web-administrative",
    ]
    assert get_workload("aether-rpa").ingress_path is None
    assert get_workload("aether-web-flow").ingress_path is None
    assert get_workload("aether-ms-auth").dockerfile_in_repo is True
    assert get_workload("ms-aeko-hub").dockerfile_in_repo is False


def test_only_kong_has_ingress_path():
    with_ingress = [w.key for w in WORKLOADS if w.ingress_path]
    assert with_ingress == ["kong"]


def test_themes_and_phrases():
    assert QA.cluster_name == "aether-qa"
    assert QA.branch == "develop"
    assert PROD.branch == "main"
    assert QA.accent == "\033[94m"
    assert QA.text == "\033[97m"
    assert PROD.accent == "\033[91m"
    assert required_phrase("aether-qa") == "yes"
    assert required_phrase("aether-prod") == "aether-prod"
    assert phrase_accepted("aether-qa", " yes ") is True
    assert phrase_accepted("aether-prod", "yes") is False
