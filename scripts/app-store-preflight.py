#!/usr/bin/env python3
"""Check local submission configuration without contacting any service."""

from __future__ import annotations

import argparse
import ipaddress
from pathlib import Path
import plistlib
import re
import sys
from urllib.parse import parse_qsl, urlsplit
from xml.parsers.expat import ExpatError


REQUIRED_API_REASONS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": "CA92.1",
    "NSPrivacyAccessedAPICategoryFileTimestamp": "C617.1",
    "NSPrivacyAccessedAPICategorySystemBootTime": "35F9.1",
}
PUBLIC_URL_KEYS = ("NilePrivacyPolicyURL", "NileSupportURL")
VENDOR_NOTICES = Path(
    "Vendor/TextRenderer/NileTextRenderer.xcframework/ios-arm64/"
    "NileTextRenderer.framework/Resources/ThirdPartyNotices"
)
LICENSE_SOURCES = {
    "FreeType-FTL.txt": VENDOR_NOTICES / "FreeType-FTL.txt",
    "HarfBuzz-COPYING.txt": VENDOR_NOTICES / "HarfBuzz-COPYING.txt",
    "Roboto-LICENSE.txt": Path("Resources/Fonts/Roboto-LICENSE.txt"),
}
RESERVED_SUFFIXES = (
    ".example", ".invalid", ".test", ".localhost", ".local", ".internal", ".lan", ".home",
)
PLACEHOLDER_DOMAINS = (
    "example.com", "example.org", "example.net", "your-domain.com", "yourdomain.com",
)
CREDENTIAL_QUERY_KEYS = {
    "token", "access_token", "refresh_token", "id_token", "api_key", "apikey", "password", "passwd",
    "secret", "client_secret", "authorization", "auth", "credential", "credentials",
    "key", "signature", "x-amz-credential", "x-amz-signature",
}


def public_url_problem(value: object) -> str | None:
    if not isinstance(value, str) or not value:
        return "is missing; configure the real public HTTPS URL before submission"
    if any(character.isspace() or ord(character) < 32 for character in value):
        return "must not contain whitespace or control characters"
    if "\\" in value:
        return "must not contain backslashes"
    if any(marker in value for marker in ("$(", "${", "<", ">", "{", "}")):
        return "contains an unresolved placeholder"
    try:
        parsed = urlsplit(value)
        hostname = parsed.hostname
        port = parsed.port
    except ValueError:
        return "is not a valid URL"
    if parsed.scheme.lower() != "https" or not hostname:
        return "must use HTTPS and a public hostname"
    if parsed.username is not None or parsed.password is not None:
        return "must not contain credentials"
    if port == 0:
        return "has an invalid port"
    if any(key.lower() in CREDENTIAL_QUERY_KEYS for key, _ in parse_qsl(parsed.query, keep_blank_values=True)):
        return "must not contain credential query parameters"
    hostname = hostname.lower().rstrip(".")
    if hostname.endswith(RESERVED_SUFFIXES) or any(
        hostname == domain or hostname.endswith("." + domain)
        for domain in PLACEHOLDER_DOMAINS
    ):
        return "uses a reserved, local, or example hostname"
    try:
        ipaddress.ip_address(hostname)
    except ValueError:
        try:
            hostname = hostname.encode("idna").decode("ascii")
        except UnicodeError:
            return "has an invalid hostname"
        labels = hostname.split(".")
        if len(labels) < 2 or not any(character.isalpha() for character in labels[-1]) or len(hostname) > 253 or any(
            re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label) is None
            for label in labels
        ):
            return "must use a valid public hostname"
    else:
        return "must use a public DNS hostname, not an IP literal"
    return None


def read_plist(path: Path, issues: list[str]) -> dict:
    try:
        with path.open("rb") as stream:
            value = plistlib.load(stream)
    except (OSError, ValueError, ExpatError, plistlib.InvalidFileException) as error:
        issues.append(f"{path.name}: cannot read a valid property list ({type(error).__name__})")
        return {}
    if not isinstance(value, dict):
        issues.append(f"{path.name}: the property list root must be a dictionary")
        return {}
    return value


def check_info(info: dict, label: str, issues: list[str]) -> None:
    for key in PUBLIC_URL_KEYS:
        problem = public_url_problem(info.get(key))
        if problem:
            # Do not print URL values: malformed configuration can contain secrets.
            issues.append(f"{label}: {key} {problem}")
    if info.get("ITSAppUsesNonExemptEncryption") is not False:
        issues.append(f"{label}: missing OS-encryption exemption; review the encryption declaration")
    ats = info.get("NSAppTransportSecurity", {})
    if not isinstance(ats, dict):
        issues.append(f"{label}: NSAppTransportSecurity must be a dictionary")
        return
    for key in (
        "NSAllowsArbitraryLoads", "NSAllowsArbitraryLoadsForMedia",
        "NSAllowsArbitraryLoadsInWebContent",
    ):
        if key in ats and ats[key] is not False:
            issues.append(f"{label}: production transport policy must not enable {key}")
    domains = ats.get("NSExceptionDomains", {})
    if not isinstance(domains, dict):
        issues.append(f"{label}: NSExceptionDomains must be a dictionary")
        return
    for exception in domains.values():
        if not isinstance(exception, dict):
            issues.append(f"{label}: each ATS domain exception must be a dictionary")
            continue
        for key in ("NSExceptionAllowsInsecureHTTPLoads", "NSTemporaryExceptionAllowsInsecureHTTPLoads"):
            if key in exception and exception[key] is not False:
                issues.append(f"{label}: production transport policy must not enable {key}")


def check_manifest(path: Path, label: str, issues: list[str]) -> None:
    manifest = read_plist(path, issues)
    if manifest.get("NSPrivacyTracking") is not False:
        issues.append(f"{label}: privacy manifest must preserve Nile's no-tracking declaration")
    if manifest.get("NSPrivacyTrackingDomains") != []:
        issues.append(f"{label}: privacy manifest must not declare tracking domains")
    declarations = manifest.get("NSPrivacyAccessedAPITypes")
    if not isinstance(declarations, list):
        issues.append(f"{label}: missing required-reason API declarations")
        return
    reasons_by_category = {}
    for declaration in declarations:
        if not isinstance(declaration, dict):
            issues.append(f"{label}: invalid required-reason API entry")
            continue
        category = declaration.get("NSPrivacyAccessedAPIType")
        reasons = declaration.get("NSPrivacyAccessedAPITypeReasons")
        if not isinstance(category, str) or not isinstance(reasons, list) or not reasons or any(
            not isinstance(reason, str) for reason in reasons
        ):
            issues.append(f"{label}: invalid required-reason API category or reasons")
            continue
        if category in reasons_by_category:
            issues.append(f"{label}: duplicate required-reason API category")
        reasons_by_category[category] = reasons
    for category, reason in REQUIRED_API_REASONS.items():
        if reason not in reasons_by_category.get(category, []):
            issues.append(f"{label}: {category} requires audited reason {reason}")


def check_resources(repo: Path, resource_root: Path, label: str, built: bool, issues: list[str]) -> None:
    check_manifest(resource_root / "PrivacyInfo.xcprivacy", label, issues)
    for name, source_path in LICENSE_SOURCES.items():
        directory = Path() if built else Path("Fonts" if name == "Roboto-LICENSE.txt" else "ThirdPartyNotices")
        try:
            expected = (repo / source_path).read_bytes()
            actual = (resource_root / directory / name).read_bytes()
        except OSError:
            issues.append(f"{label}: missing license {name} or its authoritative source")
            continue
        if not actual or actual != expected:
            issues.append(f"{label}: {name} differs from its authoritative license text")
    attribution = resource_root / ("Nile-Attributions.txt" if built else "ThirdPartyNotices/Nile-Attributions.txt")
    try:
        text = attribution.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        issues.append(f"{label}: missing readable Nile-Attributions.txt")
    else:
        if "based in part on the work of the FreeType Team" not in text:
            issues.append(f"{label}: missing required FreeType acknowledgement")


def audit(repo: Path, app_bundle: Path | None = None) -> list[str]:
    issues: list[str] = []
    source_info = read_plist(repo / "Config/Info-Release.plist", issues)
    check_info(source_info, "Release source", issues)
    check_resources(repo, repo / "Resources", "Source resources", False, issues)
    try:
        release_config = (repo / "Config/Release.xcconfig").read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        issues.append("Release source: cannot read Release.xcconfig")
    else:
        if "NILE_CLEARTEXT_GATEWAYS_SUPPORTED" in release_config:
            issues.append("Release source: cleartext gateway support must be compiled out")
    if app_bundle is not None:
        built_info = read_plist(app_bundle / "Info.plist", issues)
        check_info(built_info, "App bundle", issues)
        check_resources(repo, app_bundle, "App bundle", True, issues)
        for key in PUBLIC_URL_KEYS:
            if source_info.get(key) != built_info.get(key):
                issues.append(f"App bundle: {key} differs from the Release source; rebuild the archive")
        if built_info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
            issues.append("App bundle: submission requires a device build, not a Simulator build")
        sdk = built_info.get("DTSDKName", "")
        match = re.fullmatch(r"iphoneos(\d+)(?:\.\d+)*", sdk) if isinstance(sdk, str) else None
        if match is None or int(match[1]) < 26:
            issues.append("App bundle: submission currently requires the iOS 26 SDK or later")
    return issues


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1], help=argparse.SUPPRESS)
    parser.add_argument("--app-bundle", type=Path, help="also validate a built Release .app, including an archived app")
    arguments = parser.parse_args()
    issues = audit(arguments.repo, arguments.app_bundle)
    if issues:
        print("App Store preflight blocked:")
        for issue in issues:
            print(f"- {issue}")
        print("No network availability, signing, or App Store Connect checks were performed.")
        return 1
    scope = "source and device bundle" if arguments.app_bundle is not None else "source"
    print(f"App Store {scope} preflight passed.")
    print("Public URL availability/content, signing, App Store metadata, and full test-lab evidence still need verification.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
