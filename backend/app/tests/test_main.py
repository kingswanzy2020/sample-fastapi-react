def test_read_main(client):
    response = client.get("/api/v1")
    assert response.status_code == 200
    assert response.json() == {"message": "Hello World"}


def test_read_version(client, monkeypatch):
    monkeypatch.setenv("GIT_SHA", "a1b2c3d4")
    monkeypatch.setenv("BUILD_TIME", "2026-01-01T00:00:00Z")

    response = client.get("/api/v1/version")

    assert response.status_code == 200
    assert response.json() == {
        "version": "a1b2c3d4",
        "built_at": "2026-01-01T00:00:00Z",
    }


def test_read_version_unbuilt(client, monkeypatch):
    monkeypatch.delenv("GIT_SHA", raising=False)
    monkeypatch.delenv("BUILD_TIME", raising=False)

    response = client.get("/api/v1/version")

    assert response.json() == {"version": "unknown", "built_at": "unknown"}
