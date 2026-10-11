"""Regression tests for the local submission gate; no network or Xcode required."""

import contextlib
import importlib.util
import io
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "app_store_preflight", Path(__file__).resolve().parents[1] / "app-store-preflight.py"
)
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)


class PublicURLTests(unittest.TestCase):
    def test_accepts_public_https_paths_and_noncredential_query_parameters(self):
        for url in (
            "https://nile.app/privacy", "https://support.nile.app:443/?lang=en#contact",
            "https://bücher.de/privacy",
        ):
            with self.subTest(url=url):
                self.assertIsNone(preflight.public_url_problem(url))

    def test_rejects_missing_placeholders_insecure_and_nonpublic_urls(self):
        for url in (
            None, 17, "", "http://nile.app/privacy", "https://example.com/privacy",
            "https://privacy.example.org", "https://nile.example", "https://nile.invalid",
            "https://localhost", "https://gateway.local", "https://127.0.0.1",
            "https://10.0.0.1", "https://[::1]", "https://127.1", "https://0x7f.0.0.1",
            "https://1.1.1.1/privacy", "https://[2606:4700:4700::1111]/privacy", "https://nile.12-34",
            "https://224.0.0.1", "https://$(PRIVACY_HOST)/privacy", "https://<domain>/privacy",
            "https://nile.app:broken", "https://nile.app:0", "https://nile.app\n/privacy",
            "https://nile.app\\privacy", "https://invalid-.com",
        ):
            with self.subTest(url=url):
                self.assertIsNotNone(preflight.public_url_problem(url))

    def test_rejects_credentials_in_authority_and_query(self):
        for url in (
            "https://name:password@nile.app/privacy", "https://name@nile.app/privacy",
            "https://nile.app/privacy?access_token=private", "https://nile.app/?%61pi_key=private",
            "https://nile.app/?X-Amz-Signature=private",
            "https://nile.app/?id_token=private", "https://nile.app/?passwd=private",
            "https://nile.app/?token", "https://nile.app/?access_token=",
        ):
            with self.subTest(url=url):
                self.assertIsNotNone(preflight.public_url_problem(url))


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.repo = Path(self.temporary_directory.name)
        self.info = {
            "NilePrivacyPolicyURL": "https://nile.app/privacy",
            "NileSupportURL": "https://nile.app/support",
            "ITSAppUsesNonExemptEncryption": False,
        }
        self.manifest = {
            "NSPrivacyTracking": False,
            "NSPrivacyTrackingDomains": [],
            "NSPrivacyAccessedAPITypes": [
                {"NSPrivacyAccessedAPIType": category, "NSPrivacyAccessedAPITypeReasons": [reason]}
                for category, reason in preflight.REQUIRED_API_REASONS.items()
            ],
        }
        self.write_plist("Config/Info-Release.plist", self.info)
        self.write("Config/Release.xcconfig", "SWIFT_OPTIMIZATION_LEVEL = -O\n")
        self.write_plist("Resources/PrivacyInfo.xcprivacy", self.manifest)
        for name, path in preflight.LICENSE_SOURCES.items():
            self.write(path, f"Complete fixture license for {name}\n")
            self.write(self.resource_path(name), f"Complete fixture license for {name}\n")
        self.write(
            "Resources/ThirdPartyNotices/Nile-Attributions.txt",
            "Nile is based in part on the work of the FreeType Team.\n",
        )

    def write(self, path, content):
        destination = self.repo / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(content, encoding="utf-8")

    def write_plist(self, path, value):
        destination = self.repo / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(plistlib.dumps(value))

    def resource_path(self, name):
        directory = "Fonts" if name == "Roboto-LICENSE.txt" else "ThirdPartyNotices"
        return Path("Resources") / directory / name

    def make_bundle(self):
        bundle = self.repo / "Nile.app"
        self.write_plist("Nile.app/Info.plist", {
            **self.info, "CFBundleSupportedPlatforms": ["iPhoneOS"], "DTSDKName": "iphoneos26.5",
        })
        self.write_plist("Nile.app/PrivacyInfo.xcprivacy", self.manifest)
        for name in preflight.LICENSE_SOURCES:
            self.write(Path("Nile.app") / name, (self.repo / self.resource_path(name)).read_text())
        self.write(
            "Nile.app/Nile-Attributions.txt",
            (self.repo / "Resources/ThirdPartyNotices/Nile-Attributions.txt").read_text(),
        )
        return bundle

    def test_complete_source_passes(self):
        self.assertEqual(preflight.audit(self.repo), [])

    def test_missing_public_deployment_values_are_explicit_blockers(self):
        self.info.pop("NilePrivacyPolicyURL")
        self.info.pop("NileSupportURL")
        self.write_plist("Config/Info-Release.plist", self.info)
        issues = preflight.audit(self.repo)
        self.assertEqual(len(issues), 2)
        self.assertTrue(any("NilePrivacyPolicyURL is missing" in issue for issue in issues))
        self.assertTrue(any("NileSupportURL is missing" in issue for issue in issues))

    def test_missing_required_reason_is_blocked(self):
        self.manifest["NSPrivacyAccessedAPITypes"].pop()
        self.write_plist("Resources/PrivacyInfo.xcprivacy", self.manifest)
        self.assertTrue(any("35F9.1" in issue for issue in preflight.audit(self.repo)))

    def test_incomplete_license_is_blocked(self):
        self.write(self.resource_path("HarfBuzz-COPYING.txt"), "Incomplete\n")
        self.assertTrue(any("HarfBuzz-COPYING.txt differs" in issue for issue in preflight.audit(self.repo)))

    def test_arbitrary_and_domain_cleartext_exceptions_are_blocked(self):
        self.info["NSAppTransportSecurity"] = {
            "NSAllowsArbitraryLoads": True,
            "NSExceptionDomains": {"gateway.local": {"NSExceptionAllowsInsecureHTTPLoads": True}},
        }
        self.write_plist("Config/Info-Release.plist", self.info)
        self.assertEqual(len(preflight.audit(self.repo)), 2)

    def test_malformed_manifest_produces_diagnostics_without_crashing(self):
        self.write("Resources/PrivacyInfo.xcprivacy", "<?xml version='1.0'?><plist>")
        self.assertTrue(any("cannot read a valid property list" in issue for issue in preflight.audit(self.repo)))

    def test_complete_device_bundle_passes(self):
        self.assertEqual(preflight.audit(self.repo, self.make_bundle()), [])

    def test_simulator_and_stale_urls_are_blocked(self):
        bundle = self.make_bundle()
        self.write_plist("Nile.app/Info.plist", {
            **self.info,
            "NileSupportURL": "https://nile.app/old-support",
            "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
            "DTSDKName": "iphonesimulator26.5",
        })
        issues = preflight.audit(self.repo, bundle)
        self.assertTrue(any("differs from the Release source" in issue for issue in issues))
        self.assertTrue(any("not a Simulator build" in issue for issue in issues))

    def test_missing_packaged_license_is_blocked(self):
        bundle = self.make_bundle()
        (bundle / "FreeType-FTL.txt").unlink()
        self.assertTrue(any("App bundle: missing license FreeType-FTL.txt" in issue for issue in preflight.audit(self.repo, bundle)))

    def test_cli_reports_blockers_without_exposing_url_credentials(self):
        self.info["NilePrivacyPolicyURL"] = "https://private-name:private-secret@nile.app/privacy"
        self.write_plist("Config/Info-Release.plist", self.info)
        output = io.StringIO()
        with patch("sys.argv", ["preflight", "--repo", str(self.repo)]), contextlib.redirect_stdout(output):
            self.assertEqual(preflight.main(), 1)
        self.assertIn("must not contain credentials", output.getvalue())
        self.assertNotIn("private-name", output.getvalue())
        self.assertNotIn("private-secret", output.getvalue())


if __name__ == "__main__":
    unittest.main()
