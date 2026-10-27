"""Verify deployed research and persistence with one paid research request.

Run from a checkout: python -m scripts.cloud_smoke [--car 'Ford Model T'] [--inspect]
--inspect only reads the saved snapshot and makes no paid research request.
Uses the saved car and deployed device-token binding. Publishes research through
the existing API; never seeds cars or reads the OpenAI credential.
"""

import argparse
import json
import subprocess
import sys
from urllib.parse import unquote, urlsplit

import httpx
from pydantic import ValidationError

from carguy.learning import grade, normalize
from carguy.models import Car, Fact, ResearchState
from scripts.diagnose_research import (
    PROJECT,
    REGION,
    SERVICE,
    DiagnosticSetupError,
    gcloud_json,
    read_secret,
)

LOGGING_QUERY = (
    'resource.type="cloud_run_revision" '
    f'resource.labels.service_name="{SERVICE}" '
    'textPayload:"Research output rejected:"'
)
CHECK_MESSAGES = {
    "service_url": "The service metadata must contain an HTTPS URL without credentials or a query.",
    "device_binding": "Expected a Secret Manager binding for CARGUY_DEVICE_TOKEN.",
    "car_selection": "Expected exactly one matching car in the saved library.",
    "research_state": "Expected exactly one research state for the saved car in each snapshot.",
    "research_incomplete": "Saved research is failed or still running; inspect the saved message before retrying.",
    "status_mismatch": "The persisted research status must match the research response.",
    "persistence": "The persisted research timestamp must match the research response.",
    "facts_missing": "Expected at least one persisted published fact for the saved car.",
    "choices": "Published fact choices must be distinct with exactly one correct answer.",
}


class SmokeCheckError(Exception):
    def __init__(self, code: str):
        self.code = code


def research_state(snapshot, car_id: str) -> ResearchState:
    matches = [item for item in snapshot.get("research", []) if item.get("carId") == car_id]
    if len(matches) != 1:
        raise SmokeCheckError("research_state")
    return ResearchState.model_validate(matches[0])


def published_facts(snapshot, car_id: str) -> list[Fact]:
    facts = [
        Fact.model_validate(item)
        for item in snapshot.get("facts", [])
        if item.get("carId") == car_id and item.get("status", "published") == "published"
    ]
    for fact in facts:
        choices = [normalize(choice) for choice in fact.choices]
        if len(set(choices)) != len(choices) or sum(grade(choice, fact) for choice in fact.choices) != 1:
            raise SmokeCheckError("choices")
    return facts


def report(state: ResearchState, facts: list[Fact], device_token: str, *, inspect_only: bool = False) -> None:
    source_urls = []
    for fact in facts:
        for source in fact.sources:
            if device_token in source.url or device_token in unquote(source.url):
                continue
            if source.url not in source_urls and len(source_urls) < 3:
                source_urls.append(source.url)
    result = {"status": state.status, "publishedFacts": len(facts), "sourceURLs": source_urls}
    if inspect_only or state.status != "ready":
        # Application identification messages are needed to answer clarification questions.
        # They are not raw provider bodies; still redact the credential if echoed by a server.
        message = state.message.replace(device_token, "[redacted]")
        if device_token in unquote(message):
            message = "[Message omitted because it contains a credential]"
        result["message"] = message
    if inspect_only:
        result["inspectionOnly"] = True
    print(json.dumps(result, indent=2))


def run(car_name: str, *, inspect_only: bool = False) -> int:
    service = gcloud_json("run", "services", "describe", SERVICE, "--region=" + REGION)
    url = service["status"]["url"].rstrip("/")
    parts = urlsplit(url)
    if (
        parts.scheme != "https"
        or not parts.hostname
        or parts.username
        or parts.password
        or parts.query
        or parts.fragment
    ):
        raise SmokeCheckError("service_url")
    variables = service["spec"]["template"]["spec"]["containers"][0].get("env", [])
    bindings = [item for item in variables if item.get("name") == "CARGUY_DEVICE_TOKEN"]
    if len(bindings) != 1:
        raise SmokeCheckError("device_binding")
    reference = bindings[0].get("valueFrom", {}).get("secretKeyRef", {})
    if not reference.get("name") or not reference.get("key"):
        raise SmokeCheckError("device_binding")
    device_token = read_secret(reference["name"], reference["key"])
    with httpx.Client(timeout=30, headers={"Authorization": "Bearer " + device_token}) as client:
        response = client.get(url + "/v1/snapshot")
        response.raise_for_status()
        initial = response.json()
        matches = [car for car in initial["cars"] if car["name"].casefold() == car_name.casefold()]
        if len(matches) != 1:
            raise SmokeCheckError("car_selection")
        car = Car.model_validate(matches[0])
        if inspect_only:
            report(
                research_state(initial, car.id),
                published_facts(initial, car.id),
                device_token,
                inspect_only=True,
            )
            return 0
        print("Running one paid research request against the saved car.", flush=True)
        response = client.post(url + f"/v1/cars/{car.id}/research", timeout=210)
        response.raise_for_status()
        researched = response.json()
        response = client.get(url + "/v1/snapshot")
        response.raise_for_status()
        persisted = response.json()

    returned_state = research_state(researched, car.id)
    saved_state = research_state(persisted, car.id)
    if saved_state.updated_at != returned_state.updated_at:
        raise SmokeCheckError("persistence")
    if saved_state.status != returned_state.status:
        raise SmokeCheckError("status_mismatch")
    facts = published_facts(persisted, car.id)
    if saved_state.status not in {"ready", "needs_clarification"}:
        report(saved_state, facts, device_token)
        raise SmokeCheckError("research_incomplete")
    if saved_state.status == "ready" and not facts:
        raise SmokeCheckError("facts_missing")
    report(saved_state, facts, device_token)
    if saved_state.status == "needs_clarification":
        print(
            "Research completed; vehicle identification needs clarification. Read the saved message before another research request.",
            file=sys.stderr,
        )
        return 2
    return 0


def logging_guidance() -> None:
    print(
        "Check sanitized research diagnostics in Cloud Logging "
        f"(project {PROJECT}, region {REGION}) with this query:\n{LOGGING_QUERY}",
        file=sys.stderr,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--car", default="Ford Model T")
    parser.add_argument(
        "--inspect", action="store_true", help="Read saved status and facts without a paid research request"
    )
    args = parser.parse_args(argv)
    try:
        return run(args.car, inspect_only=args.inspect)
    except httpx.HTTPStatusError as error:
        print("Cloud smoke request failed: HTTP", error.response.status_code, file=sys.stderr)
        logging_guidance()
    except httpx.HTTPError:
        print("Cloud smoke request failed before a complete HTTP response.", file=sys.stderr)
        logging_guidance()
    except SmokeCheckError as error:
        print(
            "Cloud smoke verification failed:",
            CHECK_MESSAGES.get(error.code, "Unknown check."),
            file=sys.stderr,
        )
    except ValidationError:
        print("Cloud smoke verification failed: response model validation.", file=sys.stderr)
    except (subprocess.CalledProcessError, DiagnosticSetupError):
        print("Google Cloud credential setup failed. No secret values were displayed.", file=sys.stderr)
    except Exception:  # noqa: BLE001 -- exceptions can contain tokens, headers, or response bodies
        print(
            "Cloud smoke setup or verification failed. No exception content was displayed.", file=sys.stderr
        )
    return 1


if __name__ == "__main__":
    sys.exit(main())
