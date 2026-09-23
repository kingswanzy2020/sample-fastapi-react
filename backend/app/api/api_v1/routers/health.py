import asyncio
import typing as t

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.core.celery_app import celery_app
from app.db.session import get_db

health_router = r = APIRouter()

# Every dependency check is bounded: a readiness probe that hangs is worse
# than one that fails, because the kubelet just waits for its own timeout
# while the pod keeps taking traffic.
CHECK_TIMEOUT_SECONDS = 2.0


def _check_database(db) -> None:
    """
    Cheapest possible round trip to Postgres through the normal session.
    """
    db.execute(text("SELECT 1")).scalar()


def _check_broker() -> None:
    """
    Open a real connection to the Celery broker (redis) and drop it.

    Uses the broker URL the app is already configured with, so this cannot
    drift away from what the worker actually talks to.
    """
    connection = celery_app.connection(
        connect_timeout=CHECK_TIMEOUT_SECONDS,
        transport_options={
            "socket_connect_timeout": CHECK_TIMEOUT_SECONDS,
            "socket_timeout": CHECK_TIMEOUT_SECONDS,
        },
    )
    try:
        connection.ensure_connection(max_retries=0)
    finally:
        connection.release()


async def _run_check(check: t.Callable, *args) -> t.Dict[str, str]:
    """
    Run a blocking check in a worker thread under a hard timeout.

    asyncio.wait_for is deliberately not used: it cancels the future and
    then waits for it, and a thread already blocked on a dead socket
    cannot be cancelled -- the probe would hang for exactly as long as
    the dependency does. asyncio.wait leaves the thread behind instead
    and answers on time. A permanently wedged dependency can therefore
    leak threads up to the executor's size, after which run_in_executor
    never starts and the probe keeps failing fast, which is the wanted
    behaviour for a readiness check.
    """
    loop = asyncio.get_event_loop()
    future = loop.run_in_executor(None, check, *args)
    done, _ = await asyncio.wait({future}, timeout=CHECK_TIMEOUT_SECONDS)

    if not done:
        # Keep the abandoned future's exception from being logged as
        # "never retrieved" when it is eventually garbage collected.
        future.add_done_callback(lambda f: f.exception())
        return {
            "status": "error",
            "detail": "timed out after {}s".format(CHECK_TIMEOUT_SECONDS),
        }

    error = future.exception()
    if error is not None:
        return {"status": "error", "detail": str(error) or repr(error)}

    return {"status": "ok"}


@r.get("/health/live")
async def health_live():
    """
    Liveness probe.

    Deliberately checks nothing: a failure here gets the container killed,
    so it must never depend on Postgres, redis or any other process.
    """
    return {"status": "ok"}


@r.get("/health/ready")
async def health_ready(db=Depends(get_db)):
    """
    Readiness probe.

    Checks every backing service the app needs to serve a request. A
    failure only pulls the pod out of the Service endpoints, so it is safe
    to report the dependency that is down.
    """
    checks = {
        "database": await _run_check(_check_database, db),
        "broker": await _run_check(_check_broker),
    }

    if any(check["status"] != "ok" for check in checks.values()):
        return JSONResponse(
            status_code=503,
            content={"status": "unavailable", "checks": checks},
        )

    return {"status": "ok", "checks": checks}
