"""Build the Projects-only Sparkle appcast from a verified release artifact."""
import base64
import binascii
import re
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime

REPO = "horner/alt-tab-macos"
BRANCH = "projects-updates"
FEED_URL = f"https://raw.githubusercontent.com/{REPO}/{BRANCH}/appcast.xml"
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def version_tuple(version):
    require(isinstance(version, str) and re.fullmatch(r"\d+\.\d+\.\d+", version),
            "Appcast versions must use numeric X.Y.Z format.")
    return tuple(map(int, version.split(".")))


def encoded_bytes(value, length, label):
    try:
        decoded = base64.b64decode(value, validate=True) if isinstance(value, str) else b""
    except (ValueError, binascii.Error):
        decoded = b""
    require(len(decoded) == length and base64.b64encode(decoded).decode() == value,
            f"Invalid Sparkle {label}.")


def validate_metadata(manifest, archive):
    version_tuple(manifest.get("version"))
    sparkle = manifest.get("sparkle")
    require(isinstance(sparkle, dict), "Package has no Sparkle signing metadata; prepare a new updater-enabled version.")
    encoded_bytes(sparkle.get("signature"), 64, "Ed25519 signature")
    encoded_bytes(sparkle.get("public_key"), 32, "Ed25519 public key")
    require(type(sparkle.get("length")) is int and sparkle["length"] > 0
            and sparkle["length"] == archive.stat().st_size, "Sparkle enclosure length differs from the exact ZIP.")
    require(sparkle.get("channel") == "beta", "Projects updates must explicitly use the beta channel.")
    minimum = sparkle.get("minimum_system_version", "")
    require(isinstance(minimum, str) and re.fullmatch(r"\d+\.\d+(?:\.\d+)?", minimum),
            "Sparkle minimum macOS version is missing or invalid.")
    return sparkle


def release_url(version):
    version_tuple(version)
    return f"https://github.com/{REPO}/releases/tag/projects-v{version}"


def archive_url(version):
    version_tuple(version)
    return f"https://github.com/{REPO}/releases/download/projects-v{version}/AltTabProjects.zip"


def item_for_release(manifest, notes, published_at):
    version = manifest["version"]
    sparkle = manifest["sparkle"]
    require(isinstance(notes, str) and notes.strip(), "Public release notes must be nonempty before appcast publication.")
    require(isinstance(published_at, str), "The public release has no publication timestamp.")
    try:
        timestamp = datetime.fromisoformat(published_at.replace("Z", "+00:00"))
    except ValueError as error:
        raise RuntimeError("The public release has an invalid publication timestamp.") from error
    require(timestamp.tzinfo is not None, "The public release timestamp must include its timezone.")
    item = ET.Element("item")
    for name, value in (("title", f"AltTabProjects {version} — Friends beta"),
                        ("link", release_url(version)),
                        (f"{{{SPARKLE}}}version", version),
                        (f"{{{SPARKLE}}}shortVersionString", version),
                        (f"{{{SPARKLE}}}channel", "beta"),
                        (f"{{{SPARKLE}}}minimumSystemVersion", sparkle["minimum_system_version"]),
                        ("pubDate", format_datetime(timestamp.astimezone(timezone.utc)))):
        ET.SubElement(item, name).text = value
    ET.SubElement(item, "description", {f"{{{SPARKLE}}}format": "plain-text"}).text = notes.replace("\r\n", "\n").replace("\r", "\n").strip()
    ET.SubElement(item, "enclosure", dict(url=archive_url(version), length=str(sparkle["length"]),
                                         type="application/octet-stream", **{f"{{{SPARKLE}}}edSignature": sparkle["signature"]}))
    try:
        ET.fromstring(ET.tostring(item, encoding="utf-8"))
    except ET.ParseError as error:
        raise RuntimeError("Release notes contain characters that XML cannot represent.") from error
    return item


def item_identity(item):
    return (item.tag, tuple(sorted(item.attrib.items())), item.text if item.tag == "description" else (item.text or "").strip(),
            tuple(item_identity(child) for child in item))


def parse_feed(previous):
    require(len(previous) <= 4 * 1024 * 1024 and not re.search(br"<!\s*(?:DOCTYPE|ENTITY)", previous, re.IGNORECASE),
            "Refusing an oversized appcast or XML entity declarations.")
    try:
        feed = ET.fromstring(previous)
    except ET.ParseError as error:
        raise RuntimeError("The existing Projects appcast is invalid XML; preserve it and repair it before publishing.") from error
    channels = feed.findall("channel")
    require(feed.tag == "rss" and feed.get("version") == "2.0" and len(channels) == 1,
            "The existing Projects appcast must be an RSS 2.0 feed with one channel.")
    channel = channels[0]
    require(channel.findtext("link") == FEED_URL, "The existing appcast belongs to a different feed.")
    seen = set()
    for item in channel.findall("item"):
        version = item.findtext(f"{{{SPARKLE}}}version")
        numeric = version_tuple(version)
        require(numeric not in seen, "The existing appcast contains duplicate versions.")
        seen.add(numeric)
        require(item.findtext(f"{{{SPARKLE}}}channel") == "beta", "An existing Projects entry has an unexpected update channel.")
        enclosures = item.findall("enclosure")
        require(len(enclosures) == 1 and enclosures[0].get("url") == archive_url(version),
                "An existing appcast entry points outside its immutable Projects release ZIP.")
        encoded_bytes(enclosures[0].get(f"{{{SPARKLE}}}edSignature"), 64, "Ed25519 signature")
        require(re.fullmatch(r"[1-9]\d*", enclosures[0].get("length", "")), "An existing enclosure has an invalid byte length.")
    return feed, channel


def appcast(manifest, archive, notes, published_at, previous=None):
    validate_metadata(manifest, archive)
    item = item_for_release(manifest, notes, published_at)
    if previous is None:
        feed = ET.Element("rss", version="2.0")
        channel = ET.SubElement(feed, "channel")
        for name, value in (("title", "AltTabProjects friends updates"), ("link", FEED_URL),
                            ("description", "Signed AltTabProjects friends beta releases"), ("language", "en")):
            ET.SubElement(channel, name).text = value
    else:
        feed, channel = parse_feed(previous)
        current = version_tuple(manifest["version"])
        require(all(version_tuple(existing.findtext(f"{{{SPARKLE}}}version")) <= current for existing in channel.findall("item")),
                "The appcast already has a newer release; refusing to downgrade it.")
        for existing in channel.findall("item"):
            version = version_tuple(existing.findtext(f"{{{SPARKLE}}}version"))
            if version == current:
                require(item_identity(existing) == item_identity(item), "This appcast version already has different metadata or notes; it will not be overwritten.")
                return previous
    channel.insert(next((index for index, child in enumerate(channel) if child.tag == "item"), len(channel)), item)
    ET.indent(feed, space="  ")
    return ET.tostring(feed, encoding="utf-8", xml_declaration=True) + b"\n"
