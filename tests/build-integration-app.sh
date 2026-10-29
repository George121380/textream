#!/bin/bash
# Build the real TA module for local integration testing, without the full Xcode project.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:-$repo_root/build/TextreamTATest.app}"
mkdir -p "$app_path/Contents/MacOS"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "${TMPDIR:-/tmp}/textream-ta-module-cache" \
  "$repo_root"/Textream/Textream/TA*.swift \
  "$repo_root/tests/TAIntegrationHarness.swift" \
  -o "$app_path/Contents/MacOS/TextreamTATest"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>TextreamTATest</string>
  <key>CFBundleIdentifier</key><string>com.george121380.textream.ta-integration-test</string>
  <key>CFBundleName</key><string>Textream TA Test</string>
  <key>CFBundleDisplayName</key><string>Textream TA Test</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSpeechRecognitionUsageDescription</key><string>Transcribe meeting playback for TA reply suggestions. Apple may process the audio when on-device recognition is unavailable.</string>
  <key>NSScreenCaptureUsageDescription</key><string>Capture system playback for live meeting transcription. Screen images are not consumed or sent to OpenAI.</string>
  <key>NSAudioCaptureUsageDescription</key><string>Transcribe system playback for TA reply suggestions.</string>
</dict></plist>
PLIST
# Finder metadata can be added by synced workspaces and is rejected by codesign.
# Only remove that metadata from our generated product; preserve security attributes.
xattr -rd com.apple.FinderInfo "$app_path" 2>/dev/null || true
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"
printf 'Built local integration test: %s\n' "$app_path"
