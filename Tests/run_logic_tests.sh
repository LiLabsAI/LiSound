#!/bin/zsh
# Runs the logic test suite against the app's non-UI sources (plan9 §5).
set -euo pipefail
cd "$(dirname "$0")/.."

SDK=$(xcrun --show-sdk-path)

swiftc -O -sdk "$SDK" -target arm64-apple-macos15.0 \
  Tests/LogicTests/main.swift \
  LiSound/Audio/AudioChainError.swift \
  LiSound/Audio/RingBuffer.swift \
  LiSound/Audio/EQParameters.swift \
  LiSound/Audio/RenderDSP.swift \
  LiSound/Audio/SpectrumBars.swift \
  LiSound/Audio/DeviceManager.swift \
  LiSound/Audio/AggregateEngine.swift \
  LiSound/Presets/Preset.swift \
  LiSound/Presets/PresetStore.swift \
  LiSound/Presets/BuiltInPresets.swift \
  LiSound/Core/SettingsStore.swift \
  LiSound/Core/AppState.swift \
  LiSound/Platform/Permissions.swift \
  -o build/logic-tests

build/logic-tests
