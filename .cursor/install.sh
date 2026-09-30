#!/usr/bin/env bash
# Idempotent dependency bootstrap for the 10x Cloud Agent (Linux) environment.
#
# 10x is a macOS SwiftUI app. The app target, its Xcode test bundle, and OmpKit
# (which imports Darwin) build only on macOS with Xcode 26.x and cannot run on a
# Linux agent — the release pipeline uses a macos-15 runner for exactly that
# reason (.github/workflows/release.yml). This script sets up everything that
# DOES run on Linux:
#
#   * Ruby + xcodeproj 1.27.0  -> scripts/generate_xcodeproj.rb (regenerates
#                                 10x.xcodeproj; see AGENTS.md)
#   * Bun + the `omp` runtime  -> the OmpExtension TypeScript test suite
#
# Re-running is safe: every step checks for the tool before installing it.
set -euo pipefail

log() { printf '\n=== %s ===\n' "$*"; }

# --- Ruby toolchain for the Xcode project generator -----------------------
if ! command -v ruby >/dev/null 2>&1; then
  log "Installing Ruby"
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ruby-full build-essential
fi

# scripts/generate_xcodeproj.rb asserts this exact version and aborts on any
# other, because each xcodeproj release ships different default build settings
# that reshuffle every object UUID. Keep this in lockstep with the Gemfile pin.
XCODEPROJ_VERSION="1.27.0"
if ! gem list -i xcodeproj -v "$XCODEPROJ_VERSION" >/dev/null 2>&1; then
  log "Installing xcodeproj ${XCODEPROJ_VERSION}"
  sudo gem install xcodeproj -v "$XCODEPROJ_VERSION"
fi

# --- Bun + omp for the OmpExtension test suite ----------------------------
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
export PATH="$BUN_INSTALL/bin:$PATH"

if ! command -v bun >/dev/null 2>&1; then
  log "Installing Bun"
  curl -fsSL https://bun.sh/install | bash
fi

# OmpExtension/test/command-channel.test.ts spawns the real `omp` binary (the
# @oh-my-pi/pi-coding-agent runtime that hosts this extension) and drives it
# over RPC. The other 34 tests are pure unit tests and need only Bun.
if ! command -v omp >/dev/null 2>&1 && [ ! -x "$BUN_INSTALL/bin/omp" ]; then
  log "Installing omp (@oh-my-pi/pi-coding-agent)"
  bun add -g @oh-my-pi/pi-coding-agent
fi

log "Installed versions"
ruby --version
gem list -i xcodeproj -v "$XCODEPROJ_VERSION" >/dev/null 2>&1 && echo "xcodeproj ${XCODEPROJ_VERSION}: present"
"$BUN_INSTALL/bin/bun" --version
"$BUN_INSTALL/bin/omp" --version 2>/dev/null || true

log "Setup complete"
