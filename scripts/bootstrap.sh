#!/usr/bin/env bash
# Generates Goof.xcodeproj from project.yml.
# Requires Xcode 15.3 or later and XcodeGen (brew install xcodegen).
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null; then
  echo "XcodeGen is missing. Install it with: brew install xcodegen" >&2
  exit 1
fi
xcodegen generate
echo "Done. Open Goof.xcodeproj and press ⌘R, or run: swift test --package-path Packages/GoofCore"
