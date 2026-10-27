"""Bounded, non-content diagnostics for structured research validation failures."""

from pydantic import ValidationError

from .models import ResearchResult, ReviewResult
from .research_models import ResearchProposal, ReviewProposal

# These messages are constants raised by our validators, never provider text.
VALIDATOR_MESSAGES = frozenset(
    {
        "Source must be an HTTPS URL without credentials",
        "Choices must be distinct and include the canonical answer",
        "Exactly one multiple-choice answer must be correct",
        "Numeric alternatives must not create a second correct choice",
        "Answer variants must be short, nonempty strings",
        "Ready research must contain at least one sourced fact",
        "A resolved report needs a sourced replacement or reaffirmed fact",
        "Research needs three distinct incorrect alternatives",
    }
)


def _schema_fields() -> frozenset[str]:
    fields: set[str] = set()

    def walk(value):
        if isinstance(value, dict):
            fields.update(value.get("properties", {}))
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    for model in (ResearchResult, ReviewResult, ResearchProposal, ReviewProposal):
        walk(model.model_json_schema(by_alias=True))
    return frozenset(fields)


FIELDS = _schema_fields()


def validation_diagnostic(error: ValueError) -> dict:
    """Do not return inputs, arbitrary extra keys, upstream bodies, URLs or error reprs."""
    if isinstance(error, ValidationError):
        details = []
        for issue in error.errors(include_input=False, include_url=False)[:20]:
            path = (
                ".".join(
                    str(part) if isinstance(part, int) or part in FIELDS else "[other]"
                    for part in issue["loc"]
                )
                or "result"
            )
            # JSON syntax diagnostics can include source snippets in context; never copy them.
            item = {"field": path, "rule": issue["type"]}
            message = str(issue.get("ctx", {}).get("error", ""))
            if message in VALIDATOR_MESSAGES:
                item["reason"] = message
            details.append(item)
        return {"code": "output_validation", "errorCount": error.error_count(), "errors": details}
    if str(error) == "A claimed source was not returned by web search":
        return {"code": "unverified_source"}
    return {"code": "invalid_output"}
