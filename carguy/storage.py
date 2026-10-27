"""Atomic local storage and a Firestore adapter using the same transaction contract."""

from __future__ import annotations

import copy
import json
import sqlite3
from collections.abc import Callable
from pathlib import Path
from typing import TypeVar

T = TypeVar("T")
COLLECTIONS = (
    "cars",
    "exhibits",
    "facts",
    "attempts",
    "sessions",
    "reports",
    "research",
    "fact_versions",
    "review_jobs",
)
State = dict[str, dict[str, dict]]


def empty_state() -> State:
    return {name: {} for name in COLLECTIONS}


class SQLiteStore:
    def __init__(self, path: str):
        self.path = path
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with sqlite3.connect(path) as connection:
            connection.execute(
                "CREATE TABLE IF NOT EXISTS records (kind TEXT, id TEXT, body TEXT, PRIMARY KEY(kind,id))"
            )

    def transaction(self, operation: Callable[[State], T]) -> T:
        with sqlite3.connect(self.path, timeout=30) as connection:
            connection.execute("BEGIN IMMEDIATE")
            state = empty_state()
            for kind, identifier, body in connection.execute("SELECT kind,id,body FROM records"):
                state[kind][identifier] = json.loads(body)
            before = copy.deepcopy(state)
            result = operation(state)
            for kind in COLLECTIONS:
                for identifier, record in state[kind].items():
                    if before[kind].get(identifier) != record:
                        connection.execute(
                            "INSERT OR REPLACE INTO records VALUES (?,?,?)",
                            (kind, identifier, json.dumps(record)),
                        )
            return result


class FirestoreStore:
    """Single-user namespace; access is through the authenticated API, never direct client writes."""

    def __init__(self, project: str, database: str = "(default)"):
        from google.cloud import firestore

        self.client = firestore.Client(project=project, database=database)
        self.root = self.client.collection("carguy_users").document("personal")

    def transaction(self, operation: Callable[[State], T]) -> T:
        from google.cloud import firestore

        @firestore.transactional
        def run(transaction):
            state = empty_state()
            for kind in COLLECTIONS:
                for document in self.root.collection(kind).stream(transaction=transaction):
                    state[kind][document.id] = document.to_dict()
            before = copy.deepcopy(state)
            result = operation(state)
            writes = [
                (kind, identifier, record)
                for kind in COLLECTIONS
                for identifier, record in state[kind].items()
                if before[kind].get(identifier) != record
            ]
            if len(writes) > 450:
                raise ValueError("Sync batch exceeds 450 changed records; send smaller batches")
            for kind, identifier, record in writes:
                transaction.set(self.root.collection(kind).document(identifier), record)
            return result

        return run(self.client.transaction())
