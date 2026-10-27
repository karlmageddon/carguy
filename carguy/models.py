from __future__ import annotations

import base64
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
from pydantic.alias_generators import to_camel


class Model(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, extra="forbid", allow_inf_nan=False
    )


Identifier = Annotated[str, Field(pattern=r"^[a-zA-Z0-9_-]{1,100}$")]
Timestamp = Annotated[float, Field(ge=0, le=4102444800)]


class Exhibit(Model):
    id: Identifier
    name: str = Field(min_length=1, max_length=120)
    archived: bool = False
    updated_at: Timestamp


class Car(Model):
    id: Identifier
    name: str = Field(min_length=1, max_length=200)
    notes: str = Field(default="", max_length=3000)
    exhibit_id: Identifier | None = None
    previous_exhibit_ids: list[Identifier] = Field(default_factory=list, max_length=100)
    removed: bool = False
    photo_data: str | None = Field(default=None, max_length=350000)
    updated_at: Timestamp

    @field_validator("photo_data")
    @classmethod
    def small_jpeg(cls, value: str | None) -> str | None:
        if value is not None:
            try:
                data = base64.b64decode(value, validate=True)
            except ValueError as error:
                raise ValueError("Photo must be base64-encoded JPEG data") from error
            if len(data) > 250 * 1024 or not data.startswith(b"\xff\xd8\xff"):
                raise ValueError("Photo must be a JPEG no larger than 250 KiB")
        return value


class Source(Model):
    title: str = Field(min_length=1, max_length=300)
    url: str = Field(min_length=1, max_length=2000)

    @field_validator("url")
    @classmethod
    def https_only(cls, value: str) -> str:
        from urllib.parse import urlsplit

        parts = urlsplit(value)
        if parts.scheme != "https" or not parts.hostname or parts.username or parts.password:
            raise ValueError("Source must be an HTTPS URL without credentials")
        return value


class UnitScale(Model):
    unit: str = Field(max_length=40)
    multiplier: float = Field(gt=0)


class NumericAnswer(Model):
    value: float
    tolerance: float = Field(ge=0)
    units: list[UnitScale] = Field(min_length=1, max_length=20)


class _FactContent(Model):
    category: Literal["technical", "history", "story", "fundamentals"]
    statement: str = Field(min_length=1, max_length=1000)
    prompt: str = Field(min_length=1, max_length=500)
    answer: str = Field(min_length=1, max_length=200)
    accepted_answers: list[str] = Field(max_length=30)
    explanation: str = Field(min_length=1, max_length=2000)
    sources: list[Source] = Field(min_length=1, max_length=10)
    numeric_answer: NumericAnswer | None


class FactDraft(_FactContent):
    choices: list[str] = Field(min_length=2, max_length=6)

    @model_validator(mode="after")
    def valid_choices(self):
        from .learning import grade, normalize

        normalized = [normalize(choice) for choice in self.choices]
        if len(set(normalized)) != len(normalized) or self.answer not in self.choices:
            raise ValueError("Choices must be distinct and include the canonical answer")
        valid = {normalize(self.answer), *(normalize(x) for x in self.accepted_answers)}
        if sum(choice in valid for choice in normalized) != 1:
            raise ValueError("Exactly one multiple-choice answer must be correct")
        if sum(grade(choice, self) for choice in self.choices) != 1:
            raise ValueError("Numeric alternatives must not create a second correct choice")
        if any(not choice.strip() or len(choice) > 200 for choice in self.choices + self.accepted_answers):
            raise ValueError("Answer variants must be short, nonempty strings")
        return self


class Fact(FactDraft):
    id: Identifier
    car_id: Identifier
    revision: int = Field(ge=1)
    status: Literal["published", "flagged", "retired"] = "published"
    checked_at: Timestamp


class Attempt(Model):
    id: Identifier
    session_id: Identifier
    fact_id: Identifier
    fact_revision: int = Field(ge=1)
    response: str = Field(max_length=1000)
    correct: bool
    answered_at: Timestamp


class StudySession(Model):
    id: Identifier
    attempt_ids: list[Identifier] = Field(min_length=1, max_length=500)
    completed_at: Timestamp
    study_day: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    time_zone: str = Field(max_length=100)

    @model_validator(mode="after")
    def valid_day(self):
        from datetime import datetime
        from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

        try:
            expected = datetime.fromtimestamp(self.completed_at, ZoneInfo(self.time_zone)).date().isoformat()
        except (ZoneInfoNotFoundError, ValueError) as error:
            raise ValueError("Unknown time zone") from error
        if self.study_day != expected:
            raise ValueError("Study day must match the original completion time and time zone")
        if len(set(self.attempt_ids)) != len(self.attempt_ids):
            raise ValueError("A session cannot count the same attempt twice")
        return self


class FactReport(Model):
    id: Identifier
    fact_id: Identifier
    fact_revision: int = Field(ge=1)
    reason: str = Field(default="", max_length=2000)
    created_at: Timestamp
    status: Literal["pending", "researching", "unresolved", "corrected", "reaffirmed", "superseded"] = (
        "pending"
    )
    resolution: str = Field(default="", max_length=3000)


class PhotoCandidate(Model):
    url: str = Field(max_length=2000)
    source_url: str = Field(max_length=2000)
    caption: str = Field(max_length=1000)

    _urls = field_validator("url", "source_url")(Source.https_only.__func__)


class ResearchPhoto(PhotoCandidate):
    attribution: str = Field(min_length=1, max_length=1000)
    license: str = Field(min_length=1, max_length=200)
    license_url: str = Field(max_length=2000)
    image_data: str = Field(max_length=140000)

    _license_url = field_validator("license_url")(Source.https_only.__func__)

    @field_validator("image_data")
    @classmethod
    def compact_jpeg(cls, value: str) -> str:
        data = base64.b64decode(value, validate=True)
        if len(data) > 100 * 1024 or not data.startswith(b"\xff\xd8\xff"):
            raise ValueError("Research photo must be a JPEG no larger than 100 KiB")
        return value


class ResearchState(Model):
    car_id: Identifier
    status: Literal["researching", "ready", "needs_clarification", "failed"]
    message: str
    photo_url: str | None = None
    photo_source_url: str | None = None
    photo_caption: str | None = None
    photos: list[ResearchPhoto] = Field(default_factory=list, max_length=5)
    photo_message: str = Field(default="", max_length=500)
    updated_at: Timestamp


class Snapshot(Model):
    cars: list[Car] = Field(default_factory=list)
    exhibits: list[Exhibit] = Field(default_factory=list)
    facts: list[Fact] = Field(default_factory=list)
    attempts: list[Attempt] = Field(default_factory=list)
    sessions: list[StudySession] = Field(default_factory=list)
    reports: list[FactReport] = Field(default_factory=list)
    research: list[ResearchState] = Field(default_factory=list)


class SyncRequest(Model):
    cars: list[Car] = Field(default_factory=list, max_length=100)
    exhibits: list[Exhibit] = Field(default_factory=list, max_length=100)
    attempts: list[Attempt] = Field(default_factory=list, max_length=10000)
    sessions: list[StudySession] = Field(default_factory=list, max_length=5000)
    reports: list[FactReport] = Field(default_factory=list, max_length=1000)


class ResearchResult(Model):
    status: Literal["ready", "needs_clarification"]
    message: str = Field(max_length=3000)
    facts: list[FactDraft] = Field(max_length=20)
    photo: PhotoCandidate | None
    photo_query: str | None = Field(default=None, max_length=120)
    photos: list[ResearchPhoto] = Field(default_factory=list, max_length=5)
    photo_message: str = Field(default="", max_length=500)

    @model_validator(mode="after")
    def ready_has_facts(self):
        if self.status == "ready" and not self.facts:
            raise ValueError("Ready research must contain at least one sourced fact")
        return self


class ReviewResult(Model):
    outcome: Literal["corrected", "reaffirmed", "unresolved"]
    explanation: str = Field(min_length=1, max_length=3000)
    fact: FactDraft | None

    @model_validator(mode="after")
    def resolution_has_fact(self):
        if self.outcome != "unresolved" and self.fact is None:
            raise ValueError("A resolved report needs a sourced replacement or reaffirmed fact")
        return self
