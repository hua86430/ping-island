#!/usr/bin/env bash
# check-arch-coverage.sh — enforce file-level coverage of ARCHITECTURE.md.
#
# Coverage metric: every production Swift source file must appear (by its
# repo-relative path) somewhere in ARCHITECTURE.md — in practice, in the
# "附錄 B 檔案覆蓋矩陣" table, which is the coverage source of truth.
#
# Scope: PingIsland/ + Prototype/Sources/. Prototype/Tests/ is excluded
# (tests are not architecture; their coverage is summarized in §15).
#
# Exits 1 and prints the uncovered list if any source file is missing.

set -euo pipefail

cd "$(dirname "$0")/.."

DOC="ARCHITECTURE.md"
if [[ ! -f "$DOC" ]]; then
  echo "error: $DOC not found at repo root" >&2
  exit 2
fi

missing=()
total=0
while IFS= read -r f; do
  total=$((total + 1))
  if ! grep -qF "$f" "$DOC"; then
    missing+=("$f")
  fi
done < <(find PingIsland Prototype/Sources -name '*.swift' | sort)

covered=$((total - ${#missing[@]}))
echo "ARCHITECTURE.md coverage: $covered / $total source files"

if (( ${#missing[@]} > 0 )); then
  echo
  echo "UNCOVERED — add these to ARCHITECTURE.md (a section + the 附錄 B matrix):"
  printf '  %s\n' "${missing[@]}"
  exit 1
fi

echo "OK — 100% file-level coverage."
