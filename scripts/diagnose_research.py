"""Reproduce research with secret-safe rule diagnostics; publish no generated facts.

Run as a module from a checkout: python -m scripts.diagnose_research
Requires an authenticated Google Cloud SDK shell. Makes one paid OpenAI request.
"""

import argparse
import asyncio
import json
import subprocess
import sys

import httpx

from carguy.diagnostics import validation_diagnostic
from carguy.models import Car
from carguy.research import OpenAIResearch, ResearchUnavailable

PROJECT = "orakle-1792087003"
REGION = "us-west1"
SERVICE = "carguy-api"


class DiagnosticSetupError(Exception):
    pass


def gcloud_json(*args):
    return json.loads(
        subprocess.check_output(["gcloud", *args, "--project=" + PROJECT, "--format=json"], text=True)
    )


def read_secret(name: str, version: str) -> str:
    # Read only for actual request authentication. stdout is captured, never displayed.
    value = subprocess.check_output(
        [
            "gcloud",
            "secrets",
            "versions",
            "access",
            version,
            "--secret=" + name,
            "--project=" + PROJECT,
        ],
        text=True,
    )
    if not value or any(not 33 <= ord(char) <= 126 for char in value):
        raise DiagnosticSetupError("A credential has invalid characters. Its value has not been displayed.")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--car", default="Ford Model T")
    args = parser.parse_args()
    service = gcloud_json("run", "services", "describe", SERVICE, "--region=" + REGION)
    variables = {
        item["name"]: item for item in service["spec"]["template"]["spec"]["containers"][0].get("env", [])
    }

    def binding(variable):
        reference = variables.get(variable, {}).get("valueFrom", {}).get("secretKeyRef")
        if not reference:
            raise DiagnosticSetupError("Expected Secret Manager binding for " + variable)
        return read_secret(reference["name"], reference["key"])

    device_token = binding("CARGUY_DEVICE_TOKEN")
    key = binding("CARGUY_RESEARCH_API_KEY")
    # Use exactly the saved car identification; do not modify the library.
    with httpx.Client(timeout=30) as client:
        response = client.get(
            service["status"]["url"] + "/v1/snapshot",
            headers={"Authorization": "Bearer " + device_token},
        )
        response.raise_for_status()
        matches = [car for car in response.json()["cars"] if car["name"].casefold() == args.car.casefold()]
    if len(matches) != 1:
        raise DiagnosticSetupError("Expected exactly one matching car in the saved library.")
    researcher = OpenAIResearch()
    researcher.key = key
    researcher.model = variables.get("CARGUY_RESEARCH_MODEL", {}).get("value", "gpt-5-mini")
    print("Running one diagnostic research request. No facts will be published.", flush=True)
    try:
        result = asyncio.run(researcher.research(Car.model_validate(matches[0])))
    except ResearchUnavailable as error:
        cause = error.__cause__
        if isinstance(cause, ValueError):
            diagnostic = validation_diagnostic(cause)
        elif isinstance(cause, httpx.HTTPStatusError):
            diagnostic = {"code": "provider_http", "status": cause.response.status_code}
        elif isinstance(cause, httpx.HTTPError):
            diagnostic = {"code": "provider_transport"}
        else:
            diagnostic = {"code": "provider_incomplete_or_unconfigured"}
        print(json.dumps(diagnostic, indent=2))
        return 1
    print(
        json.dumps(
            {
                "status": result.status,
                "validatedFacts": len(result.facts),
                "note": "This fresh output passed validation. Nothing was written to the library.",
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError:
        print("Google Cloud command failed. No secret values were displayed.", file=sys.stderr)
        sys.exit(1)
    except httpx.HTTPStatusError as error:
        print("Snapshot request failed: HTTP", error.response.status_code, file=sys.stderr)
        sys.exit(1)
    except DiagnosticSetupError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except Exception as error:  # noqa: BLE001 -- redact credential-bearing exception text at CLI boundary
        # Do not print exception strings: HTTP header validation can include credential values.
        print("Diagnostic setup failed:", type(error).__name__, file=sys.stderr)
        sys.exit(1)
