import time

from app.api.api_v1.routers import health


def broker_ok():
    return None


def test_health_live_needs_no_auth_and_no_dependencies(client, monkeypatch):
    """
    Liveness must answer even when every backing service is broken.
    """

    def explode(*args, **kwargs):
        raise AssertionError("liveness must not check dependencies")

    monkeypatch.setattr(health, "_check_database", explode)
    monkeypatch.setattr(health, "_check_broker", explode)

    response = client.get("/api/v1/health/live")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_health_ready(client, monkeypatch):
    monkeypatch.setattr(health, "_check_broker", broker_ok)

    response = client.get("/api/v1/health/ready")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "checks": {
            "database": {"status": "ok"},
            "broker": {"status": "ok"},
        },
    }


def test_health_ready_database_down(client, monkeypatch):
    def database_down(db):
        raise RuntimeError("could not connect to server")

    monkeypatch.setattr(health, "_check_database", database_down)
    monkeypatch.setattr(health, "_check_broker", broker_ok)

    response = client.get("/api/v1/health/ready")
    body = response.json()

    assert response.status_code == 503
    assert body["status"] == "unavailable"
    assert body["checks"]["database"]["status"] == "error"
    assert "could not connect to server" in body["checks"]["database"]["detail"]
    assert body["checks"]["broker"] == {"status": "ok"}


def test_health_ready_broker_down(client, monkeypatch):
    def broker_down():
        raise ConnectionRefusedError("Error 111 connecting to redis:6379")

    monkeypatch.setattr(health, "_check_broker", broker_down)

    response = client.get("/api/v1/health/ready")
    body = response.json()

    assert response.status_code == 503
    assert body["status"] == "unavailable"
    assert body["checks"]["broker"]["status"] == "error"
    assert "redis:6379" in body["checks"]["broker"]["detail"]
    assert body["checks"]["database"] == {"status": "ok"}


def test_health_ready_times_out_slow_dependency(client, monkeypatch):
    """
    A hanging dependency must fail the probe rather than hang it.
    """
    monkeypatch.setattr(health, "CHECK_TIMEOUT_SECONDS", 0.1)
    monkeypatch.setattr(health, "_check_broker", lambda: time.sleep(1))

    started = time.time()
    response = client.get("/api/v1/health/ready")
    elapsed = time.time() - started
    body = response.json()

    assert response.status_code == 503
    assert elapsed < 1
    assert body["checks"]["broker"]["status"] == "error"
    assert "timed out" in body["checks"]["broker"]["detail"]
