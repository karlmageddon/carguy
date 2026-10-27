import copy
import json
import os
import subprocess
import sys
from pathlib import Path

import httpx
import pytest

from scripts import cloud_smoke

ROOT = Path(__file__).resolve().parents[1]
TOKEN = "device-sensitive-canary-keep-private"


@pytest.fixture
def deploy_shell(tmp_path):
    log = tmp_path / "gcloud.jsonl"
    executable = tmp_path / "gcloud"
    executable.write_text(
        f"#!{sys.executable}\n"
        "import json, os, sys\n"
        "args = sys.argv[1:]\n"
        "with open(os.environ['FAKE_GCLOUD_LOG'], 'a') as log:\n"
        "    log.write(json.dumps(args) + '\\n')\n"
        "if args[:3] == ['run', 'services', 'describe']:\n"
        "    if any('serviceAccountName' in arg for arg in args):\n"
        "        print(os.environ.get('FAKE_SERVICE_ACCOUNT', 'runtime@example.test'))\n"
        "    else:\n"
        "        print('https://api.example.test')\n"
        "if args[:3] == ['artifacts', 'repositories', 'describe']:\n"
        "    failure = os.environ.get('FAKE_REPOSITORY_ERROR', '')\n"
        "    if failure:\n"
        "        print('ERROR: (gcloud.artifacts.repositories.describe) ' + failure, file=sys.stderr)\n"
        "        sys.exit(4)\n"
        "if args[:2] == ['builds', 'submit']:\n"
        "    sys.exit(int(os.environ.get('FAKE_BUILD_EXIT', '0')))\n"
    )
    executable.chmod(0o755)
    env = dict(os.environ, PATH=str(tmp_path) + os.pathsep + os.environ["PATH"], FAKE_GCLOUD_LOG=str(log))
    env.pop("CARGUY_DEVICE_SECRET", None)

    def execute(*args, **overrides):
        result = subprocess.run(
            ["bash", str(ROOT / "scripts" / "deploy.sh"), *args],
            cwd=ROOT,
            env=env | overrides,
            text=True,
            capture_output=True,
            check=False,
        )
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        return result, calls

    return execute


@pytest.mark.parametrize("args", [("--unknown",), ("--image-only", "extra"), ("extra", "--image-only")])
def test_deploy_validates_arguments_before_cloud_commands(deploy_shell, args):
    result, calls = deploy_shell(*args)
    assert result.returncode == 2
    assert "Usage:" in result.stderr
    assert calls == []


def test_deploy_help_uses_no_cloud_commands(deploy_shell):
    result, calls = deploy_shell("--help")
    assert result.returncode == 0
    assert "--image-only" in result.stdout
    assert calls == []


@pytest.mark.parametrize("repository_missing", [False, True])
def test_image_only_builds_current_commit_and_only_updates_image(deploy_shell, repository_missing):
    result, calls = deploy_shell(
        "--image-only", FAKE_REPOSITORY_ERROR="NOT_FOUND: missing" if repository_missing else ""
    )
    assert result.returncode == 0, result.stderr
    commit = subprocess.check_output(["git", "rev-parse", "--short=12", "HEAD"], cwd=ROOT, text=True).strip()
    image = f"us-west1-docker.pkg.dev/orakle-1792087003/carguy/api:{commit}"
    assert calls[0][:4] == ["run", "services", "describe", "carguy-api"]
    assert "--format=value(spec.template.spec.serviceAccountName)" in calls[0]
    creates = [call for call in calls if call[:3] == ["artifacts", "repositories", "create"]]
    assert len(creates) == int(repository_missing)
    build = next(call for call in calls if call[:2] == ["builds", "submit"])
    assert build == [
        "builds",
        "submit",
        ".",
        "--project",
        "orakle-1792087003",
        "--region",
        "us-west1",
        "--config",
        "cloudbuild.yaml",
        f"--substitutions=_IMAGE={image}",
    ]
    updates = [call for call in calls if call[:3] == ["run", "services", "update"]]
    assert updates == [
        [
            "run",
            "services",
            "update",
            "carguy-api",
            "--project",
            "orakle-1792087003",
            "--region",
            "us-west1",
            "--image",
            image,
            "--quiet",
        ]
    ]
    assert not any(call[0] in {"secrets", "firestore", "iam"} for call in calls)
    assert calls[-1][-1] == "--format=value(status.url)"


def test_image_only_requires_existing_explicit_runtime_identity(deploy_shell):
    result, calls = deploy_shell("--image-only", FAKE_SERVICE_ACCOUNT="")
    assert result.returncode == 1
    assert "explicit runtime service account" in result.stderr
    assert len(calls) == 1


def test_image_only_stops_on_repository_access_failure(deploy_shell):
    result, calls = deploy_shell("--image-only", FAKE_REPOSITORY_ERROR="PERMISSION_DENIED: denied")
    assert result.returncode == 4
    assert "Resolve the access or service error" in result.stderr
    assert len(calls) == 2


def test_image_only_stops_before_update_when_build_fails(deploy_shell):
    result, calls = deploy_shell("--image-only", FAKE_BUILD_EXIT="7")
    assert result.returncode == 7
    assert calls[-1][:2] == ["builds", "submit"]


def test_no_argument_deploy_preserves_existing_configuration_mode(deploy_shell):
    result, calls = deploy_shell(CARGUY_DEVICE_SECRET="existing-device-secret")
    assert result.returncode == 0, result.stderr
    assert any(call[:3] == ["firestore", "databases", "describe"] for call in calls)
    grants = [call for call in calls if call[:2] == ["secrets", "add-iam-policy-binding"]]
    assert [call[2] for call in grants] == ["carguy-openai-key", "existing-device-secret"]
    update = next(call for call in calls if call[:3] == ["run", "services", "update"])
    assert "--timeout=300" in update
    assert (
        "--update-secrets=CARGUY_RESEARCH_API_KEY=carguy-openai-key:latest,"
        "CARGUY_DEVICE_TOKEN=existing-device-secret:latest"
    ) in update
    assert any(arg.startswith("--update-env-vars=") for arg in update)


@pytest.fixture
def smoke_setup(monkeypatch):
    service = {
        "status": {"url": "https://api.example.test"},
        "spec": {
            "template": {
                "spec": {
                    "containers": [
                        {
                            "env": [
                                {
                                    "name": "CARGUY_DEVICE_TOKEN",
                                    "valueFrom": {
                                        "secretKeyRef": {"name": "bound-device-secret", "key": "7"},
                                    },
                                },
                                {
                                    "name": "CARGUY_RESEARCH_API_KEY",
                                    "valueFrom": {
                                        "secretKeyRef": {"name": "do-not-read-openai", "key": "1"},
                                    },
                                },
                            ]
                        }
                    ]
                }
            }
        },
    }
    car = {"id": "ford-model-t", "name": "Ford Model T", "notes": "saved identity", "updatedAt": 1}
    fact = {
        "id": "saved-fact",
        "carId": car["id"],
        "revision": 1,
        "status": "published",
        "checkedAt": 100,
        "category": "technical",
        "statement": "Fixture statement",
        "prompt": "How many?",
        "answer": "4",
        "acceptedAnswers": ["four"],
        "choices": ["4", "6", "8", "12"],
        "explanation": "Fixture explanation",
        "sources": [{"title": "Fixture", "url": "https://example.org/source"}],
        "numericAnswer": None,
    }
    research = {"carId": car["id"], "status": "ready", "message": "private server message", "updatedAt": 100}
    initial = {"cars": [car], "facts": [], "research": []}
    researched = {"cars": [car], "facts": [fact], "research": [research]}
    persisted = copy.deepcopy(researched)
    cloud_calls = []
    secret_calls = []
    requests = []

    def describe(*args):
        cloud_calls.append(args)
        return service

    def secret(*args):
        secret_calls.append(args)
        assert args == ("bound-device-secret", "7")
        return TOKEN

    monkeypatch.setattr(cloud_smoke, "gcloud_json", describe)
    monkeypatch.setattr(cloud_smoke, "read_secret", secret)
    payloads = [initial, researched, persisted]
    responses = [200, 200, 200]

    def handler(request):
        assert request.headers["Authorization"] == "Bearer " + TOKEN
        requests.append(request)
        index = len(requests) - 1
        return httpx.Response(responses[index], json=payloads[index])

    original_client = httpx.Client
    monkeypatch.setattr(
        cloud_smoke.httpx,
        "Client",
        lambda **kwargs: original_client(transport=httpx.MockTransport(handler), **kwargs),
    )
    return {
        "service": service,
        "initial": initial,
        "researched": researched,
        "persisted": persisted,
        "payloads": payloads,
        "responses": responses,
        "requests": requests,
        "cloud_calls": cloud_calls,
        "secret_calls": secret_calls,
    }


def test_cloud_smoke_researches_saved_car_and_verifies_persistence(smoke_setup, capsys):
    # A successful retry may deduplicate every fact; fact count need not grow.
    smoke_setup["initial"]["facts"] = copy.deepcopy(smoke_setup["persisted"]["facts"])
    assert cloud_smoke.main([]) == 0
    assert smoke_setup["cloud_calls"] == [
        (
            "run",
            "services",
            "describe",
            "carguy-api",
            "--region=us-west1",
        )
    ]
    assert smoke_setup["secret_calls"] == [("bound-device-secret", "7")]
    requests = smoke_setup["requests"]
    assert [(request.method, request.url.path) for request in requests] == [
        ("GET", "/v1/snapshot"),
        ("POST", "/v1/cars/ford-model-t/research"),
        ("GET", "/v1/snapshot"),
    ]
    assert requests[1].extensions["timeout"]["read"] == 210
    assert requests[1].content == b""
    output = capsys.readouterr()
    assert '"status": "ready"' in output.out
    assert '"publishedFacts": 1' in output.out
    assert "https://example.org/source" in output.out
    assert TOKEN not in output.out + output.err
    assert "private server message" not in output.out + output.err


@pytest.mark.parametrize(
    "cars",
    [
        [],
        [
            {"id": "one", "name": "Ford Model T", "updatedAt": 1},
            {"id": "two", "name": "ford model t", "updatedAt": 1},
        ],
    ],
)
def test_cloud_smoke_requires_one_saved_matching_car_without_seeding(smoke_setup, capsys, cars):
    smoke_setup["initial"]["cars"] = cars
    assert cloud_smoke.main([]) == 1
    assert [request.method for request in smoke_setup["requests"]] == ["GET"]
    assert "exactly one matching car" in capsys.readouterr().err


def test_cloud_smoke_supports_explicit_saved_car_name(smoke_setup):
    smoke_setup["initial"]["cars"][0]["name"] = "Another saved car"
    assert cloud_smoke.main(["--car", "Another saved car"]) == 0


@pytest.mark.parametrize(
    "failure", ["timestamp", "not_ready", "duplicate_state", "no_facts", "flagged", "choices"]
)
def test_cloud_smoke_rejects_invalid_persisted_research(smoke_setup, capsys, failure):
    persisted = smoke_setup["persisted"]
    if failure == "timestamp":
        persisted["research"][0]["updatedAt"] = 101
    elif failure == "not_ready":
        persisted["research"][0]["status"] = "failed"
    elif failure == "duplicate_state":
        persisted["research"] *= 2
    elif failure == "no_facts":
        persisted["facts"] = []
    elif failure == "flagged":
        persisted["facts"][0]["status"] = "flagged"
    else:
        persisted["facts"][0]["choices"] = ["4", "four", "8", "12"]
    assert cloud_smoke.main([]) == 1
    assert len(smoke_setup["requests"]) == 3
    output = capsys.readouterr()
    assert "verification failed" in output.err
    assert TOKEN not in output.out + output.err
    assert "private server message" not in output.out + output.err


def test_cloud_smoke_never_prints_token_embedded_in_source_url(smoke_setup, capsys):
    smoke_setup["persisted"]["facts"][0]["sources"].append(
        {"title": "Private canary", "url": "https://example.org/" + TOKEN}
    )
    assert cloud_smoke.main([]) == 0
    output = capsys.readouterr()
    assert TOKEN not in output.out + output.err
    assert "https://example.org/source" in output.out


@pytest.mark.parametrize("index", [0, 1, 2])
def test_cloud_smoke_http_errors_show_code_and_safe_logging_query(smoke_setup, capsys, index):
    smoke_setup["responses"][index] = 503
    smoke_setup["payloads"][index] = {"detail": TOKEN + " private upstream body"}
    assert cloud_smoke.main([]) == 1
    assert len(smoke_setup["requests"]) == index + 1
    output = capsys.readouterr()
    assert "HTTP 503" in output.err
    assert cloud_smoke.LOGGING_QUERY in output.err
    assert TOKEN not in output.out + output.err
    assert "private upstream body" not in output.out + output.err


@pytest.mark.parametrize(
    "failure",
    [
        ValueError(TOKEN),
        httpx.ConnectError(TOKEN),
        subprocess.CalledProcessError(
            1,
            ["gcloud", TOKEN],
            output=TOKEN,
            stderr=TOKEN,
        ),
    ],
)
def test_cloud_smoke_exception_messages_never_expose_credentials(smoke_setup, monkeypatch, capsys, failure):
    def fail(*args):
        raise failure

    monkeypatch.setattr(cloud_smoke, "read_secret", fail)
    assert cloud_smoke.main([]) == 1
    assert smoke_setup["requests"] == []
    output = capsys.readouterr()
    assert TOKEN not in output.out + output.err
