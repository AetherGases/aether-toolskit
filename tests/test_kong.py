from aether_env.kong import KONG_ROUTES, render_kong_config


def test_kong_routes_cover_all_public_backends():
    paths = {route.path for route in KONG_ROUTES}
    assert paths == {"/auth", "/calculator", "/inventory", "/cloudinary", "/hub", "/admin", "/"}


def test_render_kong_config_declares_services_and_strip_path():
    text = render_kong_config()
    assert '_format_version: "3.0"' in text
    assert "name: aether-ms-auth" in text
    assert "strip_path: true" in text
    assert "http://aether-ms-auth.aether.svc.cluster.local:8080" in text
    assert "http://ms-aeko-hub.aether.svc.cluster.local:8000" in text
    assert "paths:" in text
    assert "          - /\n        strip_path: false" in text
