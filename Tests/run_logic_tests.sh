#!/bin/zsh
# Runs the logic test suite against the app's non-UI sources (plan9 §5).
set -euo pipefail
cd "$(dirname "$0")/.."

SDK=$(xcrun --show-sdk-path)

swiftc -O -sdk "$SDK" -target arm64-apple-macos15.0 \
  Tests/LogicTests/main.swift \
  fxsound/Audio/AudioChainError.swift \
  fxsound/Audio/RingBuffer.swift \
  fxsound/Audio/EQParameters.swift \
  fxsound/Audio/RenderDSP.swift \
  fxsound/Audio/SpectrumAnalyzer.swift \
  fxsound/Audio/DeviceManager.swift \
  fxsound/Audio/AggregateEngine.swift \
  fxsound/Presets/Preset.swift \
  fxsound/Presets/PresetStore.swift \
  fxsound/Presets/BuiltInPresets.swift \
  fxsound/Core/SettingsStore.swift \
  fxsound/Core/AppState.swift \
  fxsound/Platform/Permissions.swift \
  -o build/logic-tests

build/logic-tests
