#!/bin/bash
# GOAL Phase 10 acceptance: every metadata file within its ASC limit.
set -e
cd "$(dirname "$0")/../fastlane/metadata/en-US"

check() {
  local file=$1 limit=$2
  local len
  len=$(wc -c < "$file" | tr -d ' ')
  if [ "$len" -gt "$limit" ]; then
    echo "FAIL $file: $len > $limit"
    exit 1
  fi
  echo "PASS $file: $len/$limit"
}

check name.txt 30
check subtitle.txt 30
check keywords.txt 100
check promotional_text.txt 170
check description.txt 4000
check release_notes.txt 4000
echo "ALL METADATA WITHIN LIMITS"
