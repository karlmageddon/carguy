"""Bounded, attributed Commons photo copies; no arbitrary server-side URL fetching."""

from __future__ import annotations

import asyncio
import base64
import io
import re
from html import unescape
from urllib.parse import urlsplit

import httpx
from PIL import Image, ImageOps, UnidentifiedImageError

from .models import ResearchPhoto

HEADERS = {"User-Agent": "Carguy/1.0 (https://github.com/karlmageddon/carguy)"}
MAX_DOWNLOAD = 6 * 1024 * 1024


def plain(value: str, limit: int = 1000) -> str:
    return unescape(re.sub(r"<[^>]*>", "", value)).strip()[:limit]


def jpeg_copy(data: bytes) -> bytes:
    with Image.open(io.BytesIO(data)) as source:
        # Bound decoded memory as well as compressed download size.
        if source.width * source.height > 16_000_000:
            raise ValueError("Image dimensions exceed the photo limit")
        image = ImageOps.exif_transpose(source).convert("RGB")
        image.thumbnail((960, 720))
        for quality in (80, 65, 50, 35):
            output = io.BytesIO()
            image.save(output, format="JPEG", quality=quality, optimize=True)
            if len(output.getvalue()) <= 100 * 1024:
                return output.getvalue()
    raise ValueError("Image exceeds the stored photo limit")


def trusted_url(url: str, host: str) -> bool:
    parts = urlsplit(url)
    return (
        parts.scheme == "https"
        and parts.hostname == host
        and parts.port in (None, 443)
        and not parts.username
        and not parts.password
        and not parts.fragment
    )


async def find_photos(query: str) -> list[ResearchPhoto]:
    """Keep up to five distinct best-match JPEGs with explicit reuse/credit metadata."""
    photos, seen = [], set()
    try:
        async with asyncio.timeout(45):
            async with httpx.AsyncClient(timeout=12, headers=HEADERS, follow_redirects=False) as client:
                response = await client.get(
                    "https://commons.wikimedia.org/w/api.php",
                    params={
                        "action": "query",
                        "format": "json",
                        "formatversion": 2,
                        "generator": "search",
                        "gsrsearch": '"' + query.replace('"', "") + '" filetype:bitmap',
                        "gsrnamespace": 6,
                        "gsrlimit": 15,
                        "prop": "imageinfo",
                        "iiprop": "url|mime|sha1|extmetadata",
                        "iiurlwidth": 960,
                        "iiextmetadatafilter": "Artist|LicenseShortName|LicenseUrl",
                    },
                )
                response.raise_for_status()
                pages = response.json().get("query", {}).get("pages", [])
                for page in sorted(pages, key=lambda item: item.get("index", 999)):
                    if len(photos) == 5:
                        break
                    try:
                        info = page.get("imageinfo", [])[0]
                        digest = info.get("sha1")
                        if info.get("mime") != "image/jpeg" or not digest or digest in seen:
                            continue
                        metadata = info.get("extmetadata", {})
                        license_name = plain(metadata.get("LicenseShortName", {}).get("value", ""), 200)
                        credit = plain(metadata.get("Artist", {}).get("value", ""))
                        license_url = metadata.get("LicenseUrl", {}).get("value", "")
                        if license_url.startswith("http://creativecommons.org/"):
                            license_url = "https://" + license_url.removeprefix("http://")
                        if license_name == "Public domain" and not license_url:
                            license_url = "https://commons.wikimedia.org/wiki/Help:Public_domain"
                        reusable = re.fullmatch(
                            r"CC BY(?:-SA)? [\d.]+|CC0(?: [\d.]+)?|Public domain", license_name
                        )
                        if not reusable or not credit or not license_url:
                            continue
                        url = info.get("thumburl") or info["url"]
                        source = info["descriptionurl"]
                        if not any(
                            trusted_url(url, host) for host in ("upload.wikimedia.org", "thumb.wikimedia.org")
                        ) or not trusted_url(source, "commons.wikimedia.org"):
                            continue
                        async with client.stream("GET", url) as download:
                            download.raise_for_status()
                            content = bytearray()
                            async for chunk in download.aiter_bytes():
                                content.extend(chunk)
                                if len(content) > MAX_DOWNLOAD:
                                    raise ValueError("Image download exceeds the limit")
                        image = await asyncio.to_thread(jpeg_copy, bytes(content))
                        # Different Commons filenames can contain the same photograph.
                        encoded = base64.b64encode(image).decode()
                        if any(photo.image_data == encoded for photo in photos):
                            continue
                        photos.append(
                            ResearchPhoto(
                                url=url,
                                source_url=source,
                                caption=(
                                    "Best-match representative imagery for "
                                    + query
                                    + "; exact vehicle/variant unverified. "
                                    + plain(page.get("title", ""))
                                )[:1000],
                                attribution=credit,
                                license=license_name,
                                license_url=license_url,
                                image_data=encoded,
                            )
                        )
                        seen.add(digest)
                    except (
                        httpx.HTTPError,
                        ValueError,
                        KeyError,
                        IndexError,
                        TypeError,
                        UnidentifiedImageError,
                        Image.DecompressionBombError,
                        OSError,
                    ):
                        continue
    except (httpx.HTTPError, ValueError, TypeError, TimeoutError):
        # Photo availability must not discard otherwise validated facts.
        pass
    return photos
