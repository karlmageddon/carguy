import asyncio
import json

import httpx
import pytest
from test_api import draft

from carguy.learning import grade
from carguy.models import Car, ResearchResult
from carguy.research import OpenAIResearch, ResearchUnavailable, strict_schema


def test_numeric_grading():
    fact = draft(
        answer="4 litres",
        acceptedAnswers=[],
        choices=["4 litres", "6 litres", "8 litres", "12 litres"],
        numericAnswer={
            "value": 4,
            "tolerance": 0.05,
            "units": [{"unit": "litres", "multiplier": 1}, {"unit": "cc", "multiplier": 0.001}],
        },
    )
    assert grade("4000 cc", fact)
    assert grade("4.04 litres", fact)
    assert not grade("4.1 litres", fact)
    assert not grade("4", fact)
    assert not grade("", fact)
    assert not grade("four litres", fact)


@pytest.mark.parametrize("verified,completed", [(True, True), (False, True), (True, False)])
def test_openai_evidence_validation(monkeypatch, verified, completed):
    result = ResearchResult(status="ready", message="Done", facts=[draft()], photo=None)
    body = {
        "status": "completed" if completed else "incomplete",
        "output": [
            {
                "type": "web_search_call",
                "action": {"sources": [{"url": "https://example.org/test"}] if verified else []},
            },
            {
                "type": "message",
                "content": [
                    {"type": "output_text", "text": result.model_dump_json(by_alias=True), "annotations": []}
                ],
            },
        ],
    }

    def handler(request):
        sent = json.loads(request.content)
        assert sent["tool_choice"] == "required"
        assert sent["tools"] == [{"type": "web_search"}]
        assert sent["text"]["format"]["strict"] is True
        return httpx.Response(200, json=body)

    original = httpx.AsyncClient
    monkeypatch.setattr(
        httpx, "AsyncClient", lambda **kwargs: original(transport=httpx.MockTransport(handler), **kwargs)
    )
    researcher = OpenAIResearch()
    researcher.key = "test-fixture-not-a-key"
    call = researcher.research(Car(id="test", name="Test", updated_at=0))
    if verified and completed:
        assert asyncio.run(call).facts[0].answer == "4"
    else:
        with pytest.raises(ResearchUnavailable):
            asyncio.run(call)


def test_strict_output_schema():
    schema = strict_schema(ResearchResult.model_json_schema(by_alias=True))

    def walk(value):
        if isinstance(value, dict):
            if value.get("type") == "object":
                assert value["additionalProperties"] is False
                assert set(value["required"]) == set(value["properties"])
            assert "default" not in value
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(schema)
