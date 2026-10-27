"""Create identification-only starter cars without overwriting existing entries."""

import argparse
import os
from urllib.parse import urlsplit

import httpx

STARTERS = [
    (
        "detroit-electric-61",
        "Detroit Electric Model 61 Brougham",
        "Supplied year 1905 is unverified. Verify Model 61 and year against museum/primary sources; request placard details if inconsistent.",
    ),
    (
        "lancia-delta-s4",
        "Lancia Delta S4",
        "Confirm road Stradale versus competition car and the particular museum vehicle.",
    ),
    (
        "duesenberg-1933",
        "1933 Duesenberg",
        "Model, chassis, coachbuilder and provenance unknown. Request placard details; do not guess.",
    ),
    ("ford-model-t", "Ford Model T", "Year and body style unknown; use model-level facts until identified."),
    (
        "benz-motorwagen",
        "Benz Patent-Motorwagen",
        "Confirm original versus replica and vehicle number before provenance claims.",
    ),
    ("czinger-21c", "Czinger 21C", "Confirm variant and production specification."),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api", default="http://127.0.0.1:8080")
    parser.add_argument("--research", action="store_true", help="Call paid OpenAI research for each starter")
    args = parser.parse_args()
    parts = urlsplit(args.api)
    if parts.username or parts.password or parts.query or parts.fragment or not parts.hostname:
        parser.error("Use a plain API origin without credentials, query or fragment")
    if parts.scheme != "https" and not (
        parts.scheme == "http" and parts.hostname in ("127.0.0.1", "localhost")
    ):
        parser.error("HTTPS is required except for a local development server")
    token = os.getenv("CARGUY_DEVICE_TOKEN", "")
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    with httpx.Client(base_url=args.api, headers=headers, timeout=180) as client:
        current = client.get("/v1/snapshot")
        current.raise_for_status()
        existing = {car["id"] for car in current.json()["cars"]}
        cars = [
            {"id": identifier, "name": name, "notes": notes, "updatedAt": 0}
            for identifier, name, notes in STARTERS
            if identifier not in existing
        ]
        response = client.post("/v1/sync", json={"cars": cars})
        response.raise_for_status()
        print(
            f"Created {len(cars)} starter entries; {len(response.json()['cars'])} cars stored. No historical claims were seeded."
        )
        if args.research:
            for identifier, _, _ in STARTERS:
                response = client.post(f"/v1/cars/{identifier}/research")
                response.raise_for_status()
                state = next(r for r in response.json()["research"] if r["carId"] == identifier)
                print(f"{identifier}: {state['status']}: {state['message']}")


if __name__ == "__main__":
    main()
