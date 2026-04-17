#!/usr/bin/env bash
set -euo pipefail

# Aggregates stats across ENVX-resources, BIOL2022, and usyd-soles-edu,
# then rewrites the stats block in profile/README.md.

ORGS=(usyd-soles-edu ENVX-resources BIOL2022)
STUDENTS=1500
COURSES=3
README="profile/README.md"

echo "Enumerating repos across ${#ORGS[@]} orgs..."
REPOS=()
for org in "${ORGS[@]}"; do
  while IFS= read -r name; do
    REPOS+=("$org/$name")
  done < <(gh repo list "$org" --limit 200 --json name --jq '.[].name')
done
echo "Found ${#REPOS[@]} repos total."

TOTAL_STARS=0
TOTAL_FORKS=0
CONTRIBUTOR_LOGINS=""

for full in "${REPOS[@]}"; do
  info=$(gh repo view "$full" --json stargazerCount,forkCount 2>/dev/null || echo '{"stargazerCount":0,"forkCount":0}')
  stars=$(jq -r '.stargazerCount // 0' <<<"$info")
  forks=$(jq -r '.forkCount // 0' <<<"$info")
  TOTAL_STARS=$((TOTAL_STARS + stars))
  TOTAL_FORKS=$((TOTAL_FORKS + forks))

  # Contributors — paginate, extract logins, append
  logins=$(gh api "/repos/$full/contributors" --paginate --jq '.[].login' 2>/dev/null || true)
  CONTRIBUTOR_LOGINS+="$logins"$'\n'
done

# Dedupe contributors, exclude bots
CONTRIBUTORS=$(printf '%s\n' "$CONTRIBUTOR_LOGINS" \
  | grep -v '^$' \
  | grep -v '\[bot\]$' \
  | sort -u \
  | wc -l \
  | xargs)

# Merged PRs via search API (one call per org)
MERGED_PRS=0
for org in "${ORGS[@]}"; do
  count=$(gh api "search/issues?q=org:$org+is:pr+is:merged&per_page=1" --jq '.total_count' 2>/dev/null || echo 0)
  MERGED_PRS=$((MERGED_PRS + count))
done

DATE=$(date -u +"%Y-%m-%d")

echo "Stats: stars=$TOTAL_STARS forks=$TOTAL_FORKS contributors=$CONTRIBUTORS prs=$MERGED_PRS"

# Shields.io badges. Using your brand palette where possible.
STUDENTS_BADGE="https://img.shields.io/badge/Students%2Fyear-~${STUDENTS}-1a355e?style=for-the-badge"
COURSES_BADGE="https://img.shields.io/badge/Open_courses-${COURSES}-e64626?style=for-the-badge"
CONTRIBUTORS_BADGE="https://img.shields.io/badge/Contributors-${CONTRIBUTORS}-8f9ec9?style=for-the-badge"
STARS_BADGE="https://img.shields.io/badge/Stars-${TOTAL_STARS}-fcc419?style=for-the-badge"
FORKS_BADGE="https://img.shields.io/badge/Forks-${TOTAL_FORKS}-2ea043?style=for-the-badge"
PRS_BADGE="https://img.shields.io/badge/Merged_PRs-${MERGED_PRS}-276DC3?style=for-the-badge"

# Build the new stats block
BLOCK=$(cat <<EOF
<!-- STATS:START -->
<div align="center">

![Students/year](${STUDENTS_BADGE})
![Open courses](${COURSES_BADGE})
![Contributors](${CONTRIBUTORS_BADGE})

![Stars](${STARS_BADGE})
![Forks](${FORKS_BADGE})
![Merged PRs](${PRS_BADGE})

<sub>Auto-updated weekly · last updated ${DATE}</sub>

</div>
<!-- STATS:END -->
EOF
)

# Replace the block in the README (requires existing markers)
python3 - <<PYEOF
import re, pathlib
p = pathlib.Path("$README")
text = p.read_text()
new = """$BLOCK"""
pattern = re.compile(r'<!-- STATS:START -->.*?<!-- STATS:END -->', re.DOTALL)
if not pattern.search(text):
    raise SystemExit("Markers <!-- STATS:START --> / <!-- STATS:END --> not found in README.")
p.write_text(pattern.sub(new, text))
print("README updated.")
PYEOF
