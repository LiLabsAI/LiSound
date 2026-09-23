#!/bin/zsh
# Runs the logic test suite against the app's non-UI sources (plan9 §5).
set -euo pipefail
cd "$(dirname "$0")/.."

SDK=$(xcrun --show-sdk-path)

swiftc -O -sdk "$SDK" -target arm64-apple-macos15.0 \
  Tests/LogicTests/main.swift \
  sovate/Audio/AudioChainError.swift \
  sovate/Audio/RingBuffer.swift \
  sovate/Audio/EQParameters.swift \
  sovate/Audio/RenderDSP.swift \
  sovate/Audio/SpectrumBars.swift \
  sovate/Audio/DeviceManager.swift \
  sovate/Audio/AggregateEngine.swift \
  sovate/Presets/Preset.swift \
  sovate/Presets/PresetStore.swift \
  sovate/Presets/BuiltInPresets.swift \
  sovate/Core/SettingsStore.swift \
  sovate/Core/AppState.swift \
  sovate/Platform/Permissions.swift \
  -o build/logic-tests

build/logic-tests
