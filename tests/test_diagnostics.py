import json

from pydantic import ValidationError
from test_api import draft

from carguy.diagnostics import validation_diagnostic
from carguy.models import ResearchResult


def test_choice_failure_explains_rule_without_provider_content():
    data = {
        "status": "ready",
        "message": "private upstream text",
        "facts": [draft().model_dump(by_alias=True)],
        "photo": None,
    }
    data["facts"][0]["answer"] = "private answer not in choices"
    try:
        ResearchResult.model_validate(data)
    except ValidationError as error:
        diagnostic = validation_diagnostic(error)
    assert diagnostic["code"] == "output_validation"
    assert diagnostic["errors"][0] == {
        "field": "facts.0",
        "rule": "value_error",
        "reason": "Choices must be distinct and include the canonical answer",
    }
    assert "private" not in json.dumps(diagnostic)


def test_extra_keys_and_syntax_context_are_not_exposed():
    secret_marker = "sk-sensitive-input-canary"
    for value in (json.dumps({secret_marker: "private"}), '{"private-data":'):
        try:
            ResearchResult.model_validate_json(value)
        except ValidationError as error:
            diagnostic = validation_diagnostic(error)
        serialized = json.dumps(diagnostic)
        assert secret_marker not in serialized
        assert "private" not in serialized


def test_source_and_unknown_failures_do_not_echo_content():
    assert validation_diagnostic(ValueError("A claimed source was not returned by web search")) == {
        "code": "unverified_source"
    }
    assert validation_diagnostic(ValueError("sk-sensitive-input-canary")) == {"code": "invalid_output"}


def test_diagnostic_command_reads_existing_car_and_does_not_publish(monkeypatch, capsys):
    import httpx

    from carguy.research import ResearchUnavailable
    from scripts import diagnose_research as command

    service = {
        "status": {"url": "https://api.example.test"},
        "spec": {
            "template": {
                "spec": {
                    "containers": [
                        {
                            "env": [
                                {"name": name, "valueFrom": {"secretKeyRef": {"name": name, "key": "1"}}}
                                for name in ("CARGUY_DEVICE_TOKEN", "CARGUY_RESEARCH_API_KEY")
                            ]
                        }
                    ]
                }
            }
        },
    }
    monkeypatch.setattr(command, "gcloud_json", lambda *args: service)
    secret_marker = "sk-sensitive-input-canary"
    monkeypatch.setattr(command, "read_secret", lambda *args: secret_marker)
    monkeypatch.setattr("sys.argv", ["diagnose_research"])
    requests = []

    def handler(request):
        requests.append(request)
        assert request.method == "GET"
        assert request.headers["Authorization"] == "Bearer " + secret_marker
        return httpx.Response(
            200,
            json={
                "cars": [
                    {"id": "ford", "name": "Ford Model T", "notes": "saved identification", "updatedAt": 0}
                ]
            },
        )

    original = httpx.Client
    monkeypatch.setattr(
        command.httpx, "Client", lambda **kwargs: original(transport=httpx.MockTransport(handler), **kwargs)
    )

    async def fail(self, car):
        assert car.notes == "saved identification"
        assert self.key == secret_marker
        raise ResearchUnavailable("private provider content") from ValueError(
            "A claimed source was not returned by web search"
        )

    monkeypatch.setattr(command.OpenAIResearch, "research", fail)
    assert command.main() == 1
    assert len(requests) == 1
    output = capsys.readouterr()
    assert "unverified_source" in output.out
    assert secret_marker not in output.out + output.err
    assert "private provider content" not in output.out + output.err
