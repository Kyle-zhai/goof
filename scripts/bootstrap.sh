#!/usr/bin/env bash
# Generates Kuro.xcodeproj. Requires Xcode 15.3+ and XcodeGen (brew install xcodegen).
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f Config.xcconfig ] || cp Config.example.xcconfig Config.xcconfig
command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
xcodegen generate
echo "Done. Open Kuro.xcodeproj, or run: swift test --package-path Packages/KuroCore"
