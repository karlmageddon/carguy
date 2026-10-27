"""Provider-only question proposals; stored/API facts retain the existing choices format."""

from typing import Annotated, Literal

from pydantic import Field, model_validator

from .learning import grade, normalize
from .models import Model, PhotoCandidate, ResearchResult, ReviewResult, _FactContent


class FactProposal(_FactContent):
    # Extra candidates let us discard repeated/correct options without inventing alternatives.
    distractors: list[Annotated[str, Field(min_length=1, max_length=200)]] = Field(min_length=3, max_length=8)

    def assembled_choices(self) -> list[str]:
        choices = [self.answer]
        seen = {normalize(self.answer)}
        for candidate in self.distractors:
            normalized = normalize(candidate)
            if not normalized or normalized in seen or grade(candidate, self):
                continue
            choices.append(candidate)
            seen.add(normalized)
            if len(choices) == 4:
                break
        return choices

    @model_validator(mode="after")
    def enough_incorrect_options(self):
        if len(self.assembled_choices()) != 4:
            raise ValueError("Research needs three distinct incorrect alternatives")
        return self

    def fact_payload(self) -> dict:
        return {
            **self.model_dump(by_alias=True, exclude={"distractors"}),
            "choices": self.assembled_choices(),
        }


class ResearchProposal(Model):
    status: Literal["ready", "needs_clarification"]
    message: str = Field(max_length=3000)
    facts: list[FactProposal] = Field(max_length=20)
    photo: PhotoCandidate | None

    def validated_result(self) -> ResearchResult:
        return ResearchResult.model_validate(
            {
                **self.model_dump(by_alias=True, exclude={"facts"}),
                "facts": [fact.fact_payload() for fact in self.facts],
            }
        )


class ReviewProposal(Model):
    outcome: Literal["corrected", "reaffirmed", "unresolved"]
    explanation: str = Field(min_length=1, max_length=3000)
    fact: FactProposal | None

    def validated_result(self) -> ReviewResult:
        return ReviewResult.model_validate(
            {
                **self.model_dump(by_alias=True, exclude={"fact"}),
                "fact": self.fact.fact_payload() if self.fact else None,
            }
        )
