#!/bin/sh
# Run every tests/test-*.sh and report. Exit non-zero if any case failed.
cd "$(dirname "$0")" || exit 1
total=0
# Both implementations face the same cases. `sh tests/run.sh sh` restricts it.
SHELLS=${1:-"sh pwsh"}
for s in $SHELLS; do
  printf '\n=== hooks %s ===\n' "$s"
  for t in test-*.sh; do
    [ -f "$t" ] || continue
    printf '%s\n' "$t"
    GS_SHELL="$s" sh "$t" || total=$((total + 1))
  done
done
if [ "$total" -eq 0 ]; then
  printf '\nAll green.\n'
else
  printf '\n%s test file(s) failed.\n' "$total"
fi
exit "$total"
