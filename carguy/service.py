from __future__ import annotations

import hashlib
import time
from uuid import uuid4

from .learning import grade
from .models import Car, Fact, FactReport, ResearchResult, ReviewResult, Snapshot, SyncRequest


class Conflict(ValueError):
    pass


def document(model) -> dict:
    return model.model_dump(by_alias=True)


def snapshot(state) -> Snapshot:
    return Snapshot.model_validate({name: list(state[name].values()) for name in Snapshot.model_fields})


def merge_sync(state, incoming: SyncRequest) -> Snapshot:
    for kind in ("exhibits", "cars"):
        for model in getattr(incoming, kind):
            record = document(model)
            existing = state[kind].get(model.id)
            if existing is None or record["updatedAt"] > existing["updatedAt"]:
                if kind == "cars" and record["exhibitId"] and record["exhibitId"] not in state["exhibits"]:
                    raise Conflict("Car refers to an unknown exhibit")
                state[kind][model.id] = record

    for attempt in incoming.attempts:
        record = document(attempt)
        existing = state["attempts"].get(attempt.id)
        if existing:
            if {k: v for k, v in existing.items() if k != "correct"} != {
                k: v for k, v in record.items() if k != "correct"
            }:
                raise Conflict("An attempt ID cannot be reused for different activity")
            continue
        current = state["facts"].get(attempt.fact_id)
        version = state["fact_versions"].get(f"{attempt.fact_id}_{attempt.fact_revision}")
        if current and current["revision"] == attempt.fact_revision:
            version = current
        if not version:
            raise Conflict("Attempt refers to a fact revision that is not on this server")
        record["correct"] = grade(attempt.response, Fact.model_validate(version))
        state["attempts"][attempt.id] = record

    for session in incoming.sessions:
        record = document(session)
        existing = state["sessions"].get(session.id)
        if existing and existing != record:
            raise Conflict("A completed session is immutable")
        for identifier in session.attempt_ids:
            attempt = state["attempts"].get(identifier)
            if (
                not attempt
                or attempt["sessionId"] != session.id
                or attempt["answeredAt"] > session.completed_at
            ):
                raise Conflict("Session must reference its own completed attempts")
        state["sessions"][session.id] = record

    for report in incoming.reports:
        existing = state["reports"].get(report.id)
        if existing:
            if any(
                existing[key] != document(report)[key]
                for key in ("factId", "factRevision", "reason", "createdAt")
            ):
                raise Conflict("A report ID cannot be reused")
            continue
        fact = state["facts"].get(report.fact_id)
        if not fact:
            raise Conflict("Report refers to an unknown fact")
        record = document(report)
        record["status"] = "pending"
        record["resolution"] = ""
        if fact["revision"] != report.fact_revision:
            record["status"] = "superseded"
            record["resolution"] = "This fact has already been revised. Review the latest version."
        else:
            fact["status"] = "flagged"
        state["reports"][report.id] = record
    return snapshot(state)


def research_identity(car: Car) -> str:
    return hashlib.sha256((car.name + "\n" + car.notes).encode()).hexdigest()


def begin_research(state, car_id: str):
    car = Car.model_validate(state["cars"][car_id])
    previous = state["research"].get(car_id)
    if previous and previous["status"] == "researching" and previous["updatedAt"] > time.time() - 300:
        raise Conflict("Research is already in progress")
    started = time.time()
    state["research"][car_id] = {
        "carId": car_id,
        "status": "researching",
        "message": "Researching sources…",
        "photoUrl": None,
        "photoSourceUrl": None,
        "photoCaption": None,
        "updatedAt": started,
    }
    return car, started


def finish_research(state, car: Car, started: float, result: ResearchResult):
    current = state["research"].get(car.id)
    if not current or current["updatedAt"] != started:
        raise Conflict("A newer research request has replaced this one")
    if research_identity(Car.model_validate(state["cars"][car.id])) != research_identity(car):
        raise Conflict("Car identification changed during research; research the updated entry")
    now = time.time()
    # Keep published facts stable on a normal retry. Re-checking a fact goes through its report/revision flow.
    existing_statements = {
        f["statement"].casefold()
        for kind in ("facts", "fact_versions")
        for f in state[kind].values()
        if f["carId"] == car.id
    }
    for draft in result.facts:
        if draft.statement.casefold() in existing_statements:
            continue
        fact = Fact(**draft.model_dump(), id=uuid4().hex, car_id=car.id, revision=1, checked_at=now)
        state["facts"][fact.id] = document(fact)
        state["fact_versions"][f"{fact.id}_1"] = document(fact)
        existing_statements.add(draft.statement.casefold())
    state["research"][car.id] = {
        "carId": car.id,
        "status": result.status,
        "message": result.message,
        "photoUrl": result.photo.url if result.photo else None,
        "photoSourceUrl": result.photo.source_url if result.photo else None,
        "photoCaption": result.photo.caption if result.photo else None,
        "updatedAt": now,
    }
    return snapshot(state)


def begin_review(state, report_id: str):
    report = FactReport.model_validate(state["reports"][report_id])
    fact = Fact.model_validate(state["facts"][report.fact_id])
    if report.status not in ("pending", "unresolved", "researching"):
        raise Conflict("This report has already been resolved")
    lease = state["review_jobs"].get(report_id)
    if lease and lease["startedAt"] > time.time() - 300:
        raise Conflict("This fact is already being re-checked")
    # The fact stays quarantined even when the provider call fails or the process restarts.
    state["reports"][report_id]["status"] = "researching"
    started = time.time()
    state["review_jobs"][report_id] = {"startedAt": started}
    return Car.model_validate(state["cars"][fact.car_id]), fact, report, started


def finish_review(state, fact: Fact, report: FactReport, started: float, result: ReviewResult):
    if state["review_jobs"][report.id]["startedAt"] != started:
        raise Conflict("A newer fact review has replaced this one")
    current = state["facts"][fact.id]
    if current["revision"] != fact.revision:
        raise Conflict("This fact was revised by another review; sync its current version")
    state["reports"][report.id]["status"] = result.outcome
    state["reports"][report.id]["resolution"] = result.explanation
    state["review_jobs"][report.id]["startedAt"] = 0
    if result.outcome != "unresolved":
        state["fact_versions"][f"{fact.id}_{fact.revision}"] = document(fact)
        updated = Fact(
            **result.fact.model_dump(),
            id=fact.id,
            car_id=fact.car_id,
            revision=fact.revision + 1,
            checked_at=time.time(),
        )
        state["facts"][fact.id] = document(updated)
        state["fact_versions"][f"{fact.id}_{updated.revision}"] = document(updated)
        for other in state["reports"].values():
            if (
                other["id"] != report.id
                and other["factId"] == fact.id
                and other["status"] in ("pending", "researching", "unresolved")
            ):
                other["status"] = "superseded"
                other["resolution"] = "A related report produced a new fact revision."
    return snapshot(state)
