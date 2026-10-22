#!/usr/bin/env python3
"""Fast, offline source-regression tests for high-risk HTMLApp release invariants.

These checks supplement—not replace—Xcode builds and simulator/device tests.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
def source(path):
    return (root / path).read_text(encoding="utf-8")

release = source("HTMLAppV3/HTMLAppWhatsNewView.swift")
project = source("project.yml")
workflow = source(".github/workflows/build.yml")
bridge = source("HTMLAppV3/EditorWeb.swift")
native = source("HTMLAppV3/NativeAPIBridge.swift")
core = source("HTMLAppV3/AppCore.swift")
ai = source("HTMLAppV3/AIGenerationService.swift")
telemetry = source("HTMLAppV3/ForgeRunTelemetry.swift")
cache = source("HTMLAppV3/SupportCore.swift")

version = re.search(r'static let compiledVersion = "([^"]+)"', release).group(1)
build = re.search(r'static let compiledBuild = "([^"]+)"', release).group(1)
assert f'MARKETING_VERSION: "{version}"' in project, "Project version and compiled version differ"
assert f'CURRENT_PROJECT_VERSION: "{build}"' in project, "Project build and compiled build differ"
assert 'workflow_dispatch:' in workflow and '\n  push:' not in workflow, "Workflow must stay manual-only"
assert 'awk -F' in workflow and "Repair and validate built app and widget version metadata" in workflow
assert "mekapc.hostish.site" not in workflow and "mekapc.hostish.site" not in source("scripts/deliver-widgets.sh")
assert "message.frameInfo.isMainFrame" in bridge, "Iframe-to-native messaging must remain blocked"
assert '["file", "about", "applewebdata"].contains(scheme)' in bridge
assert 'withPermission(.clipboard, id: id)' in native, "Clipboard read requires per-app consent"
assert 'withPermission(.files, id: id)' in native, "Files picker requires per-app consent"
assert 'case files' in source("HTMLAppV3/PermissionSystem.swift")
assert 'includePersonalData: false' in core, "Nearby export must omit personal state"
assert 'includePersonalData: false' in source("HTMLAppV3/NearbyAppTransfer.swift"), "Nearby import must ignore old personal state"
assert 'blocking.isEmpty' in ai and 'qaRepairResponseBytes' in ai, "Local clean QA should not send unnecessary repair requests"
assert 'HTMLAppPackageTransfer' in core

assert "library.corrupt-" in core and "libraryBackupURL" in core
assert "guard !libraryLoadBlocked" in core, "No writes after unreadable Library load"
assert "HTMLQualityChecks.blockingIssues" in ai
assert "normalizeDocument" in ai and 'phase = "Repairing confirmed app error"' in ai
assert "case .repair:" in telemetry and "guard let matched = run.slices.lastIndex" in telemetry
assert "maxAppBytes" in cache and "maxFileBytes" in cache
for obsolete in ("HTMLApp/HTMLApp.swift", "HTMLApp/HTMLAppV2.swift", "HTMLApp/HTMLAppV3.swift"):
    assert not (root / obsolete).exists(), "Old unused app entry point remains: " + obsolete

print(f"HTMLApp source invariants passed for {version} ({build}); IPA packaging still requires an Xcode build.")
