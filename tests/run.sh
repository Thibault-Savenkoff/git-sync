#!/bin/sh
# Run every tests/test-*.sh and report. Exit non-zero if any case failed.
cd "$(dirname "$0")" || exit 1
total=0
for t in test-*.sh; do
  [ -f "$t" ] || continue
  printf '%s\n' "$t"
  sh "$t" || total=$((total + 1))
done
if [ "$total" -eq 0 ]; then
  printf '\nTout est vert.\n'
else
  printf '\n%s fichier(s) de test en echec.\n' "$total"
fi
exit "$total"
