import time
from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient

from carguy.main import create_app
from carguy.models import Car, FactDraft, ResearchResult, ReviewResult
from carguy.research import ResearchUnavailable
from carguy.storage import SQLiteStore


def draft(**changes):
    data = {
        "category": "technical",
        "statement": "This test engine has four cylinders.",
        "prompt": "How many cylinders?",
        "answer": "4",
        "acceptedAnswers": ["four"],
        "choices": ["4", "6", "8", "12"],
        "explanation": "A test fixture, not a published car claim.",
        "sources": [{"title": "Fixture", "url": "https://example.org/test"}],
        "numericAnswer": None,
    }
    return FactDraft.model_validate(data | changes)


class Researcher:
    available = True

    async def research(self, car):
        return ResearchResult(status="ready", message="Fixture researched", facts=[draft()], photo=None)

    async def review(self, car, fact, report):
        return ReviewResult(
            outcome="corrected",
            explanation="Reviewed fixture",
            fact=draft(answer="6", choices=["4", "6", "8", "12"], acceptedAnswers=["six"]),
        )


@pytest.fixture
def client(tmp_path):
    return TestClient(
        create_app(
            store=SQLiteStore(str(tmp_path / "test.sqlite")), researcher=Researcher(), token="test-device"
        )
    )


AUTH = {"Authorization": "Bearer test-device"}


def sync(client, **body):
    return client.post("/v1/sync", json=body, headers=AUTH)


def seed(client):
    car = Car(id="car", name="Test car", updated_at=time.time()).model_dump(by_alias=True)
    assert sync(client, cars=[car]).status_code == 200
    response = client.post("/v1/cars/car/research", headers=AUTH)
    assert response.status_code == 200
    return car, response.json()["facts"][0]


def attempt(fact, identifier="attempt", session="session", **changes):
    return {
        "id": identifier,
        "sessionId": session,
        "factId": fact["id"],
        "factRevision": fact["revision"],
        "response": "four",
        "correct": False,
        "answeredAt": time.time(),
    } | changes


def test_auth_and_health(client):
    assert client.get("/health").json()["authenticationRequired"] is True
    assert client.get("/v1/snapshot").status_code == 401
    assert client.post("/v1/cars/missing/research", headers=AUTH).status_code == 404


def test_history_revisions_reports_and_removed_car(client):
    car, fact = seed(client)
    original = attempt(fact)
    first = sync(client, attempts=[original]).json()
    assert first["attempts"][0]["correct"] is True  # server grades, not client
    report = {
        "id": "report",
        "factId": fact["id"],
        "factRevision": 1,
        "reason": "Check engine",
        "createdAt": time.time(),
    }
    assert sync(client, reports=[report]).json()["facts"][0]["status"] == "flagged"
    reviewed = client.post("/v1/reports/report/review", headers=AUTH).json()
    assert reviewed["facts"][0]["revision"] == 2
    assert reviewed["reports"][0]["status"] == "corrected"
    # An offline answer to revision 1 still has its original grading after correction.
    late = attempt(fact, identifier="late")
    now = time.time()
    session = {
        "id": "session",
        "attemptIds": ["attempt", "late"],
        "completedAt": now,
        "studyDay": datetime.fromtimestamp(now, UTC).date().isoformat(),
        "timeZone": "UTC",
    }
    car.update(removed=True, updatedAt=now)
    result = sync(client, cars=[car], attempts=[late], sessions=[session])
    assert result.status_code == 200
    data = result.json()
    assert data["cars"][0]["removed"]
    assert all(a["correct"] for a in data["attempts"])
    assert len(data["sessions"]) == 1 and len(data["facts"]) == 1
    assert sync(client, attempts=[original], sessions=[session]).status_code == 200
    assert sync(client, attempts=[original | {"response": "8"}]).status_code == 409


def test_transaction_rollback_and_timestamp_merge(client):
    car, _ = seed(client)
    moved = car | {"name": "Should roll back", "updatedAt": time.time()}
    bad = {"id": "orphan", "name": "Unknown exhibit", "exhibitId": "missing", "updatedAt": time.time()}
    assert sync(client, cars=[moved, bad]).status_code == 409
    data = client.get("/v1/snapshot", headers=AUTH).json()
    assert data["cars"][0]["name"] == "Test car"
    assert (
        sync(client, cars=[car | {"name": "Stale", "updatedAt": 0}]).json()["cars"][0]["name"] == "Test car"
    )


def test_research_failure_quarantines_report(client):
    _, fact = seed(client)
    report = {
        "id": "report",
        "factId": fact["id"],
        "factRevision": 1,
        "reason": "Check",
        "createdAt": time.time(),
    }
    sync(client, reports=[report])

    async def fail(*args):
        raise ResearchUnavailable("Provider unavailable")

    client.app.dependency_overrides.clear()
    # Inject through create_app rather than touching external provider credentials.
    researcher = Researcher()
    researcher.review = fail
    failing = TestClient(create_app(store=client.app.state.store, researcher=researcher, token="test-device"))
    assert failing.post("/v1/reports/report/review", headers=AUTH).status_code == 503
    data = failing.get("/v1/snapshot", headers=AUTH).json()
    assert data["facts"][0]["status"] == "flagged"
    assert data["reports"][0]["status"] == "unresolved"


def test_validation(client):
    assert sync(client, cars=[{"id": "../x", "name": "x", "updatedAt": 0}]).status_code == 422
    assert (
        sync(client, cars=[{"id": "x", "name": "x", "updatedAt": 0, "photoData": "not jpeg"}]).status_code
        == 422
    )
    assert (
        sync(
            client,
            sessions=[
                {
                    "id": "s",
                    "attemptIds": ["a"],
                    "completedAt": 0,
                    "studyDay": "2026-01-01",
                    "timeZone": "UTC",
                }
            ],
        ).status_code
        == 422
    )
    with pytest.raises(ValueError):
        draft(choices=["4", "four", "6", "8"])


def test_sqlite_persistence(tmp_path):
    path = str(tmp_path / "persistent.sqlite")
    first = TestClient(create_app(store=SQLiteStore(path), researcher=Researcher(), token="test-device"))
    seed(first)
    second = TestClient(create_app(store=SQLiteStore(path), researcher=Researcher(), token="test-device"))
    assert len(second.get("/v1/snapshot", headers=AUTH).json()["facts"]) == 1


def test_plaque_photo_sync_roundtrip_and_validation(client):
    import base64

    jpeg = base64.b64encode(b"\xff\xd8\xffplaque-fixture").decode()
    car = {
        "id": "plaque-car",
        "name": "Plaque fixture",
        "updatedAt": 1,
        "notes": "Museum plaque transcription:\nReviewed fixture text",
        "plaquePhotoData": jpeg,
    }
    response = sync(client, cars=[car])
    assert response.status_code == 200
    saved = next(c for c in response.json()["cars"] if c["id"] == car["id"])
    assert saved["plaquePhotoData"] == jpeg
    assert saved["photoData"] is None
    assert saved["notes"] == car["notes"]
    assert sync(client, cars=[car | {"plaquePhotoData": "not a jpeg"}]).status_code == 422
    too_large = base64.b64encode(b"\xff\xd8\xff" + b"x" * (250 * 1024)).decode()
    assert sync(client, cars=[car | {"plaquePhotoData": too_large}]).status_code == 422
