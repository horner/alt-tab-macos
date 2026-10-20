import base64
import copy
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

import updates


class UpdateFeedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="Projects appcast tests ")
        self.addCleanup(self.temp.cleanup)
        self.archive = Path(self.temp.name) / "AltTabProjects.zip"
        self.archive.write_bytes(b"the exact notarized and stapled final ZIP")
        self.manifest = dict(version="1.0.6", sparkle=dict(signature=base64.b64encode(b"s" * 64).decode(),
                             public_key=base64.b64encode(b"k" * 32).decode(), length=self.archive.stat().st_size,
                             minimum_system_version="12.0", channel="beta"))
        self.published_at = "2026-10-20T17:00:00Z"
        self.notes = "Fix search & focus.\nKeep <Projects> and preferences."

    def generate(self, manifest=None, previous=None, notes=None):
        return updates.appcast(manifest or self.manifest, self.archive, self.notes if notes is None else notes,
                               self.published_at, previous)

    def test_feed_fields_describe_exact_zip_and_explicit_beta_channel(self):
        content = self.generate()
        channel = ET.fromstring(content).find("channel")
        self.assertEqual(channel.findtext("link"), updates.FEED_URL)
        item = channel.find("item")
        self.assertEqual(item.findtext(f"{{{updates.SPARKLE}}}version"), self.manifest["version"])
        self.assertEqual(item.findtext(f"{{{updates.SPARKLE}}}shortVersionString"), self.manifest["version"])
        self.assertEqual(item.findtext(f"{{{updates.SPARKLE}}}channel"), "beta")
        self.assertEqual(item.findtext(f"{{{updates.SPARKLE}}}minimumSystemVersion"), "12.0")
        self.assertEqual(item.findtext("pubDate"), "Tue, 20 Oct 2026 17:00:00 +0000")
        self.assertEqual(item.findtext("description"), self.notes)
        self.assertEqual(item.find("description").get(f"{{{updates.SPARKLE}}}format"), "plain-text")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"), updates.archive_url("1.0.6"))
        self.assertEqual(enclosure.get("length"), str(self.archive.stat().st_size))
        self.assertEqual(enclosure.get(f"{{{updates.SPARKLE}}}edSignature"), self.manifest["sparkle"]["signature"])
        self.assertEqual(enclosure.get("type"), "application/octet-stream")

    def test_release_notes_are_escaped_as_text(self):
        content = self.generate(notes="<script>alert('bad')</script> & text ]]> remain text.")
        self.assertNotIn(b"<script>", content)
        self.assertIn(b"&lt;script&gt;", content)
        self.assertEqual(ET.fromstring(content).findtext("channel/item/description"),
                         "<script>alert('bad')</script> & text ]]> remain text.")

    def test_invalid_xml_characters_in_notes_stop_before_publication(self):
        for notes in ("Release notes\x00", "Release\x0bnotes", "Release notes\ud800"):
            with self.subTest(notes=repr(notes)), self.assertRaisesRegex(RuntimeError, "XML cannot represent"):
                self.generate(notes=notes)

    def test_resume_with_same_release_is_byte_identical(self):
        previous = self.generate()
        self.assertEqual(self.generate(previous=previous), previous)

    def test_resume_normalizes_release_notes_line_endings(self):
        for notes in ("First line\r\nSecond line", "First line\rSecond line"):
            previous = self.generate(notes=notes)
            with self.subTest(notes=notes):
                self.assertEqual(self.generate(previous=previous, notes=notes), previous)

    def test_new_release_retains_previous_entries(self):
        previous = self.generate()
        newer = copy.deepcopy(self.manifest)
        newer["version"] = "1.0.7"
        feed = self.generate(newer, previous=previous)
        items = ET.fromstring(feed).findall("channel/item")
        self.assertEqual([item.findtext(f"{{{updates.SPARKLE}}}version") for item in items], ["1.0.7", "1.0.6"])
        old = ET.fromstring(previous).find("channel/item")
        self.assertEqual(updates.item_identity(items[1]), updates.item_identity(old))

    def test_newer_feed_cannot_be_downgraded(self):
        older = copy.deepcopy(self.manifest)
        older["version"] = "1.0.5"
        with self.assertRaisesRegex(RuntimeError, "newer release"):
            self.generate(older, previous=self.generate())

    def test_hidden_newer_entry_cannot_be_bypassed_by_matching_first_item(self):
        feed = ET.fromstring(self.generate())
        channel = feed.find("channel")
        newer = copy.deepcopy(self.manifest)
        newer["version"] = "1.0.7"
        channel.append(updates.item_for_release(newer, self.notes, self.published_at))
        with self.assertRaisesRegex(RuntimeError, "newer release"):
            self.generate(previous=ET.tostring(feed))

    def test_existing_version_is_immutable(self):
        previous = self.generate()
        for field, value in (("signature", base64.b64encode(b"x" * 64).decode()), ("minimum_system_version", "13.0")):
            edited = copy.deepcopy(self.manifest)
            edited["sparkle"][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(RuntimeError, "not be overwritten"):
                self.generate(edited, previous=previous)
        with self.assertRaisesRegex(RuntimeError, "not be overwritten"):
            self.generate(previous=previous, notes="Replacement notes")

    def test_missing_or_invalid_signature_key_length_channel_and_minimum_are_rejected(self):
        for field, value in (("signature", "not-base64"), ("signature", base64.b64encode(b"s" * 32).decode()),
                             ("public_key", ""), ("public_key", base64.b64encode(b"k" * 64).decode()),
                             ("length", self.archive.stat().st_size + 1), ("length", True), ("length", 0),
                             ("channel", None), ("channel", "stable"), ("minimum_system_version", ""),
                             ("minimum_system_version", "macOS 12")):
            edited = copy.deepcopy(self.manifest)
            edited["sparkle"][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(RuntimeError):
                self.generate(edited)

    def test_missing_metadata_rejects_bootstrap_package_without_update_support(self):
        with self.assertRaisesRegex(RuntimeError, "no Sparkle signing metadata"):
            self.generate(dict(version="1.0.5"))

    def test_versions_and_release_timestamp_are_validated(self):
        for version in ("1.0", "1.0.6beta", "1.0.6?token=x", "1.0.6/../../", None):
            with self.subTest(version=version), self.assertRaises(RuntimeError):
                self.generate(dict(self.manifest, version=version))
        for timestamp in (None, "bad", "2026-10-20T12:00:00"):
            with self.subTest(timestamp=timestamp), self.assertRaises(RuntimeError):
                updates.appcast(self.manifest, self.archive, self.notes, timestamp)
        with self.assertRaisesRegex(RuntimeError, "nonempty"):
            self.generate(notes="  ")

    def test_existing_feed_must_belong_to_projects(self):
        previous = self.generate().replace(updates.FEED_URL.encode(), b"https://example.invalid/other.xml")
        with self.assertRaisesRegex(RuntimeError, "different feed"):
            self.generate(previous=previous)

    def test_existing_feed_cannot_reference_foreign_archive_or_implicit_channel(self):
        for path, field, value in (("channel/item/enclosure", "url", "https://example.invalid/app.zip"),
                                   ("channel/item/enclosure", "length", "-1"),
                                   (f"channel/item/{{{updates.SPARKLE}}}channel", None, "stable")):
            feed = ET.fromstring(self.generate())
            element = feed.find(path)
            if field:
                element.set(field, value)
            else:
                element.text = value
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                self.generate(previous=ET.tostring(feed))

    def test_duplicate_versions_invalid_xml_and_entities_are_rejected(self):
        feed = ET.fromstring(self.generate())
        feed.find("channel").append(copy.deepcopy(feed.find("channel/item")))
        for previous in (ET.tostring(feed), b"<rss", b'<!DOCTYPE rss [<!ENTITY x "value">]><rss/>', b"x" * (4 * 1024 * 1024 + 1)):
            with self.subTest(prefix=previous[:30]), self.assertRaises(RuntimeError):
                self.generate(previous=previous)


if __name__ == "__main__":
    unittest.main()
