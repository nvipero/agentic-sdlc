#!/usr/bin/env bash
# The factory's own backlog project: set an issue's status, or list the
# issues that are open work (In Progress or Blocked) without an open pull
# request, which is what an interrupted session leaves behind.
#
#   scripts/backlog.sh status <issue> "Todo|Blocked|In Progress|In Review|Done"
#   scripts/backlog.sh stale
set -euo pipefail

OWNER=nvipero PROJECT=2 REPO=nvipero/agentic-sdlc

items() {
  gh api graphql -f owner="$OWNER" -F number="$PROJECT" -f query='
    query($owner: String!, $number: Int!) { user(login: $owner) { projectV2(number: $number) {
      id field(name: "Status") { ... on ProjectV2SingleSelectField { id options { id name } } }
      items(first: 100) { nodes { id content { ... on Issue { number } }
        fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } } } } } } }' \
    --jq '.data.user.projectV2'
}

case "${1:-}" in
  status)
    issue="${2:?issue number}" name="${3:?status}"
    p="$(items)"
    item="$(jq -r --argjson n "$issue" '.items.nodes[] | select(.content.number == $n) | .id' <<<"$p")"
    option="$(jq -r --arg s "$name" '.field.options[] | select(.name == $s) | .id' <<<"$p")"
    [ -n "$item" ] || { echo "issue #$issue is not in the project" >&2; exit 1; }
    [ -n "$option" ] || { echo "no status \"$name\"" >&2; exit 1; }
    gh project item-edit --project-id "$(jq -r .id <<<"$p")" --id "$item" \
      --field-id "$(jq -r .field.id <<<"$p")" --single-select-option-id "$option" >/dev/null
    echo "#$issue: $name"
    ;;
  stale)
    open_prs="$(gh pr list -R "$REPO" --state open --json body,headRefName --jq '.[] | .body + " " + .headRefName')"
    items | jq -r '.items.nodes[] | select(.fieldValueByName.name == "In Progress" or .fieldValueByName.name == "Blocked")
      | "\(.content.number)|\(.fieldValueByName.name)"' |
    while IFS='|' read -r n s; do
      grep -qE "#$n([^0-9]|$)" <<<"$open_prs" || echo "#$n is $s with no open pull request"
    done
    ;;
  *) sed -n '2,7p' "$0" >&2; exit 2 ;;
esac
