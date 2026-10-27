import asyncio
import base64
import io
import json

import httpx
import pytest
from PIL import Image

from carguy.models import Car, ResearchPhoto, ResearchResult
from carguy.photos import find_photos, jpeg_copy
from carguy.service import begin_research, finish_research
from carguy.storage import COLLECTIONS, SQLiteStore


def image_bytes(color):
    output = io.BytesIO()
    Image.new("RGB", (300, 200), color).save(output, format="JPEG")
    return output.getvalue()


def page(index, **overrides):
    info = {
        "mime": "image/jpeg",
        "sha1": str(index),
        "thumburl": f"https://thumb.wikimedia.org/car-{index}.jpg",
        "descriptionurl": f"https://commons.wikimedia.org/wiki/File:Car-{index}.jpg",
        "extmetadata": {
            "Artist": {"value": "<a>Test photographer</a>"},
            "LicenseShortName": {"value": "CC BY-SA 4.0"},
            "LicenseUrl": {"value": "https://creativecommons.org/licenses/by-sa/4.0/"},
        },
    } | overrides
    return {"title": f"File:Car {index}.jpg", "index": index, "imageinfo": [info]}


def install_transport(monkeypatch, pages, images=None):
    requests = []

    def handler(request):
        requests.append(request)
        assert "authorization" not in request.headers
        if request.url.host == "commons.wikimedia.org":
            assert '"Ford Model T"' in request.url.params["gsrsearch"]
            return httpx.Response(200, json={"query": {"pages": pages}})
        content = (images or {}).get(request.url.path, image_bytes((len(requests) * 25 % 255, 20, 30)))
        return httpx.Response(200, content=content)

    original = httpx.AsyncClient
    monkeypatch.setattr(
        httpx, "AsyncClient", lambda **kw: original(transport=httpx.MockTransport(handler), **kw)
    )
    return requests


def test_five_distinct_credited_photos_are_compact_and_firestore_sized(monkeypatch):
    install_transport(monkeypatch, [page(i) for i in range(1, 9)])
    photos = asyncio.run(find_photos("Ford Model T"))
    assert len(photos) == 5
    assert len({p.image_data for p in photos}) == 5
    for photo in photos:
        assert photo.attribution == "Test photographer"
        assert "representative" in photo.caption and "unverified" in photo.caption
        data = base64.b64decode(photo.image_data)
        assert len(data) <= 100 * 1024
        with Image.open(io.BytesIO(data)) as image:
            assert image.format == "JPEG"
            assert image.width <= 960 and image.height <= 720
    assert len(json.dumps([p.model_dump(by_alias=True) for p in photos]).encode()) < 800_000


def test_duplicates_bad_images_and_untrusted_hosts_do_not_fill_gallery(monkeypatch):
    pages = [
        page(1),
        page(2, sha1="1"),
        page(3, thumburl="https://127.0.0.1/private"),
        page(4),
        page(5),
        page(6, mime="image/svg+xml"),
    ]
    same = image_bytes("blue")
    requests = install_transport(
        monkeypatch, pages, {"/car-1.jpg": same, "/car-4.jpg": same, "/car-5.jpg": b"not an image"}
    )
    photos = asyncio.run(find_photos("Ford Model T"))
    assert len(photos) == 1
    assert all(r.url.host in {"commons.wikimedia.org", "thumb.wikimedia.org"} for r in requests)


def test_unavailable_photo_search_does_not_break_fact_research(monkeypatch):
    original = httpx.AsyncClient

    def unavailable(request):
        return httpx.Response(503)

    monkeypatch.setattr(
        httpx, "AsyncClient", lambda **kw: original(transport=httpx.MockTransport(unavailable), **kw)
    )
    assert asyncio.run(find_photos("Ford Model T")) == []


def test_oversized_decoded_images_are_rejected():
    output = io.BytesIO()
    Image.new("RGB", (4100, 4100)).save(output, format="PNG")
    with pytest.raises(ValueError, match="dimensions"):
        jpeg_copy(output.getvalue())


def test_partial_best_matches_and_previous_gallery_survive_research(tmp_path):
    state = {name: {} for name in COLLECTIONS}
    car = Car(id="ford", name="Ford Model T", updated_at=0)
    state["cars"][car.id] = car.model_dump(by_alias=True)

    def photo(index):
        return ResearchPhoto(
            url=f"https://upload.wikimedia.org/{index}.jpg",
            source_url=f"https://commons.wikimedia.org/wiki/File:{index}.jpg",
            caption="Representative",
            attribution="Photographer",
            license="CC0",
            license_url="https://creativecommons.org/publicdomain/zero/1.0/",
            image_data=base64.b64encode(image_bytes((index * 50, 0, 0))).decode(),
        )

    state["research"][car.id] = {
        "photos": [photo(1).model_dump(by_alias=True)],
        "status": "ready",
        "updatedAt": 0,
    }
    _, started = begin_research(state, car.id)
    assert len(state["research"][car.id]["photos"]) == 1
    result = ResearchResult(
        status="needs_clarification",
        message="Best judgment",
        facts=[],
        photo=None,
        photos=[photo(2)],
        photo_message="Two best matches available",
    )
    saved = finish_research(state, car, started, result)
    assert len(saved.research[0].photos) == 2
    assert saved.research[0].photos[0].source_url.endswith("2.jpg")
    assert saved.research[0].photo_message == result.photo_message
    # Real data, not transient URLs, persists through the snapshot contract.
    assert saved.research[0].photos[0].image_data

    store = SQLiteStore(str(tmp_path / "gallery.sqlite"))
    store.transaction(lambda database: database.update(state))
    reopened = SQLiteStore(str(tmp_path / "gallery.sqlite"))
    assert reopened.transaction(lambda database: database["research"][car.id]["photos"]) == [
        p.model_dump(by_alias=True) for p in saved.research[0].photos
    ]


def test_best_judgment_photo_query_runs_even_when_identification_needs_clarification(monkeypatch):
    from carguy.research import OpenAIResearch

    queries = []
    result = ResearchResult(
        status="needs_clarification",
        message="Year uncertain",
        facts=[],
        photo=None,
        photo_query="Ford Model T",
    )

    async def request(*args):
        return result

    async def photos(query):
        queries.append(query)
        return []

    researcher = OpenAIResearch()
    monkeypatch.setattr(researcher, "_request", request)
    monkeypatch.setattr("carguy.research.find_photos", photos)
    actual = asyncio.run(researcher.research(Car(id="ford", name="Ford, year uncertain", updated_at=0)))
    assert queries == ["Ford Model T"]
    assert actual is result
    assert "Fewer than three" in actual.photo_message
