from aether_env.__main__ import main


def test_main_stops_when_aws_key_is_absent(monkeypatch):
    monkeypatch.delenv("AWS_ACCESS_KEY_ID", raising=False)
    code = main({})
    assert code == 2
