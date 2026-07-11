#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  mapfile_command=(git ls-files -co --exclude-standard -z)
else
  mapfile_command=(find . -type f \
    -not -path './.git/*' \
    -not -path './.build/*' \
    -not -path './dist/*' \
    -not -name '.DS_Store' -print0)
fi

files=()
while IFS= read -r -d '' file; do
  files+=("$file")
done < <("${mapfile_command[@]}")

if ((${#files[@]} == 0)); then
  echo "audit: no project files found"
  exit 1
fi

failed=0
for file in "${files[@]}"; do
  normalized="${file#./}"
  case "$normalized" in
    .env|.env.*|*.pem|*.key|*.p12|*.mobileprovision|session.json)
      echo "audit: blocked sensitive filename: $normalized"
      failed=1
      ;;
  esac

  if [[ -f "$file" ]]; then
    size=$(stat -f '%z' "$file")
    if ((size > 10 * 1024 * 1024)); then
      echo "audit: file larger than 10 MiB: $normalized ($size bytes)"
      failed=1
    fi
  fi
done

text_files=()
for file in "${files[@]}"; do
  if [[ -f "$file" ]] && file "$file" | grep -qE 'text|JSON|XML|shell script|source'; then
    text_files+=("$file")
  fi
done

if ((${#text_files[@]} > 0)); then
  secret_pattern='(/Users/[A-Za-z0-9._-]+/|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----)'
  if grep -En "$secret_pattern" "${text_files[@]}"; then
    echo "audit: possible personal path or credential found"
    failed=1
  fi
fi

if ((failed != 0)); then
  exit 1
fi

echo "audit: passed (${#files[@]} project files checked)"
