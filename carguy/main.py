from __future__ import annotations

import hmac
import os
import time
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool

from .models import Snapshot, SyncRequest
from .research import OpenAIResearch, ResearchUnavailable
from .service import (
    Conflict,
    begin_research,
    begin_review,
    finish_research,
    finish_review,
    merge_sync,
    snapshot,
)
from .storage import FirestoreStore, SQLiteStore


def create_app(store=None, researcher=None, token: str | None = None) -> FastAPI:
    mode = os.getenv("CARGUY_ENV", "development")
    token = token if token is not None else os.getenv("CARGUY_DEVICE_TOKEN", "")
    store_mode = os.getenv("CARGUY_STORE", "sqlite")
    if mode != "development" and (len(token) < 32 or store_mode != "firestore"):
        raise RuntimeError("Production requires Firestore and a device token of at least 32 characters")
    if store is None:
        store = (
            FirestoreStore(
                os.environ["CARGUY_PROJECT_ID"], os.getenv("CARGUY_FIRESTORE_DATABASE", "(default)")
            )
            if store_mode == "firestore"
            else SQLiteStore(os.getenv("CARGUY_DB_PATH", ".data/carguy.sqlite"))
        )
    researcher = researcher or OpenAIResearch()

    async def authorize(request: Request):
        if token:
            supplied = request.headers.get("Authorization", "")
            if not hmac.compare_digest(supplied.encode(), ("Bearer " + token).encode()):
                raise HTTPException(401, "Pair this device with the API in Settings")
        elif mode != "development":
            raise HTTPException(503, "Authentication is not configured")

    @asynccontextmanager
    async def lifespan(app):
        yield

    app = FastAPI(title="Carguy API", version="0.1.0", lifespan=lifespan)
    app.state.store = store

    @app.exception_handler(Conflict)
    async def conflict_handler(request, error):
        return JSONResponse(status_code=409, content={"detail": str(error)})

    @app.exception_handler(ResearchUnavailable)
    async def research_handler(request, error):
        return JSONResponse(status_code=503, content={"detail": str(error)})

    @app.get("/health")
    async def health():
        return {
            "status": "ok",
            "storage": store_mode,
            "researchConfigured": researcher.available,
            "authenticationRequired": bool(token),
        }

    @app.get("/v1/snapshot", response_model=Snapshot, dependencies=[Depends(authorize)])
    async def get_snapshot():
        return await run_in_threadpool(store.transaction, snapshot)

    @app.post("/v1/sync", response_model=Snapshot, dependencies=[Depends(authorize)])
    async def sync(body: SyncRequest):
        return await run_in_threadpool(store.transaction, lambda state: merge_sync(state, body))

    @app.post("/v1/cars/{car_id}/research", response_model=Snapshot, dependencies=[Depends(authorize)])
    async def research(car_id: str):
        if not researcher.available:
            raise ResearchUnavailable(
                "Configure CARGUY_RESEARCH_API_KEY on the backend to enable OpenAI research."
            )
        try:
            car, started = await run_in_threadpool(
                store.transaction, lambda state: begin_research(state, car_id)
            )
        except KeyError:
            raise HTTPException(404, "Car not found")
        try:
            result = await researcher.research(car)
            return await run_in_threadpool(
                store.transaction, lambda state: finish_research(state, car, started, result)
            )
        except (ResearchUnavailable, Conflict) as error:
            message = str(error)

            def fail(state):
                current = state["research"].get(car_id)
                if current and current["updatedAt"] == started:
                    current.update(status="failed", message=message, updatedAt=time.time())

            await run_in_threadpool(store.transaction, fail)
            raise

    @app.post("/v1/reports/{report_id}/review", response_model=Snapshot, dependencies=[Depends(authorize)])
    async def review(report_id: str):
        if not researcher.available:
            raise ResearchUnavailable("Configure CARGUY_RESEARCH_API_KEY on the backend to re-check facts.")
        try:
            car, fact, report, started = await run_in_threadpool(
                store.transaction, lambda state: begin_review(state, report_id)
            )
        except KeyError:
            raise HTTPException(404, "Report not found")
        try:
            result = await researcher.review(car, fact, report)
            return await run_in_threadpool(
                store.transaction, lambda state: finish_review(state, fact, report, started, result)
            )
        except ResearchUnavailable as error:
            message = str(error)

            def fail(state):
                if (
                    state["review_jobs"][report_id]["startedAt"] == started
                    and state["reports"][report_id]["status"] == "researching"
                ):
                    state["reports"][report_id].update(status="unresolved", resolution=message)
                    state["review_jobs"][report_id]["startedAt"] = 0

            await run_in_threadpool(store.transaction, fail)
            raise

    return app


app = create_app()
