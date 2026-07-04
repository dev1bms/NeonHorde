#!/bin/sh
# Xcode Cloud post-clone hook.
#
# NeonHorde.xcodeproj is GENERATED from project.yml by XcodeGen and is
# deliberately gitignored (GOAL §5: never hand-edit the .xcodeproj). Xcode
# Cloud clones the bare repo, so the project must be generated here, before
# Xcode Cloud resolves and builds it.
set -e
set -x

# Repo root: Xcode Cloud provides CI_PRIMARY_REPOSITORY_PATH; fall back to
# the parent of ci_scripts/ so the script also works locally.
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO_ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
    # Homebrew is preinstalled on Xcode Cloud macOS runners.
    export HOMEBREW_NO_AUTO_UPDATE=1
    export HOMEBREW_NO_INSTALL_CLEANUP=1
    brew install xcodegen
fi

xcodegen generate

if [ ! -d "NeonHorde.xcodeproj" ]; then
    echo "ERROR: ci_post_clone failed — NeonHorde.xcodeproj was not generated" >&2
    exit 1
fi
echo "ci_post_clone: NeonHorde.xcodeproj generated successfully"
