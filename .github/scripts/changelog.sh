#!/usr/bin/env bash
# Laver release-noter for den aktuelle version i WastedCoast.toc:
# kun commits siden versionen sidst blev ændret, uden Co-Authored-By/Claude-Session-linjer.
# Brug: .github/scripts/changelog.sh > CHANGELOG-release.md
set -euo pipefail
toc=WastedCoast/WastedCoast.toc
ver_at() { git show "$1:$toc" 2>/dev/null | grep -m1 -i '^## Version:' | sed 's/^## [Vv]ersion:[[:space:]]*//' | tr -d '\r[:space:]'; }
current=$(ver_at HEAD)

# Find den seneste commit, hvor .toc havde en anden version end nu.
prev=""
for c in $(git log --first-parent --format=%H -- "$toc"); do
  if [ "$(ver_at "$c")" != "$current" ]; then prev=$c; break; fi
done
range=${prev:+$prev..}HEAD

echo "# Wasted Coast Forever v$current"
echo
git log --first-parent --format='%x1e%s%n%b' "$range" -- WastedCoast \
  | awk -v RS='\x1e' '
      NF == 0 { next }
      {
        n = split($0, lines, "\n"); out = ""; first = 1
        for (i = 1; i <= n; i++) {
          l = lines[i]
          if (l ~ /^(Co-Authored-By|Claude-Session|Signed-off-by):/ || l ~ /claude\.ai\/code/) continue
          if (first) { if (l == "") continue; sub(/^Merge #[0-9]+: /, "", l); out = "- " l; first = 0 }
          else if (l == "") out = out "\n"
          else out = out "\n  " l
        }
        sub(/\n+$/, "", out)
        if (out != "") print out
      }'
