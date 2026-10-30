#!/usr/bin/env bash
# Sets up GitHub for a factory project (or the factory repo itself).
# Runs on the host with the owner's gh login. Every subcommand is idempotent.
#
#   scripts/setup-github.sh ruleset           <owner/repo> [factory]
#   scripts/setup-github.sh interaction-limit <owner/repo>
#   scripts/setup-github.sh secret-scanning   <owner/repo>
#   scripts/setup-github.sh actions           <owner/repo>   (project: restricted Actions, step 4)
#   scripts/setup-github.sh actions-off       <owner/repo>   (the factory repo: no workflows)
#   scripts/setup-github.sh code-scanning     <owner/repo>   (CodeQL default setup)
#   scripts/setup-github.sh preview-env       <owner/repo>   (environment for the Vercel token)
#   scripts/setup-github.sh labels            <owner/repo>
#   scripts/setup-github.sh board             <owner/repo>
#   scripts/setup-github.sh status            <owner/repo>   (read-only)
set -euo pipefail
export GH_PAGER=cat   # gh would open a pager for every call in a terminal

die() { echo "setup-github: $*" >&2; exit 1; }
say() { echo "setup-github: $*" >&2; }

RULESET_NAME="protect-main"

# A project's ruleset (step 4, plan decision 5): every change through a pull
# request with the code owner's (the owner's) approval, dismissed by a new push;
# the gate checks required from GitHub Actions (app 15368) and CodeQL alerts
# blocking. One bypass actor: the admin role, in pull request mode, so the
# owner's own PRs can merge without a second reviewer, never by direct push.
# The agents' App is not an admin. With "factory" as the third argument
# (the factory repo, which runs no workflows): no checks, no bypass.
ruleset() {
  local nwo="$1" kind="${2:-project}" id body bypass checks
  bypass='[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}]'
  checks=',{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,
   "do_not_enforce_on_create":false,"required_status_checks":[
    {"context":"guards","integration_id":15368},{"context":"unit-and-build","integration_id":15368},
    {"context":"acceptance","integration_id":15368},{"context":"dependency-review","integration_id":15368}]}},
  {"type":"code_scanning","parameters":{"code_scanning_tools":[
    {"tool":"CodeQL","security_alerts_threshold":"high_or_higher","alerts_threshold":"errors"}]}}'
  local approvals=1 owner_review=true
  if [ "$kind" = factory ]; then bypass='[]'; checks=''; approvals=0; owner_review=false; fi
  body="{\"name\":\"protect-main\",\"target\":\"branch\",\"enforcement\":\"active\",\"bypass_actors\":$bypass,
 \"conditions\":{\"ref_name\":{\"include\":[\"~DEFAULT_BRANCH\"],\"exclude\":[]}},
 \"rules\":[{\"type\":\"pull_request\",\"parameters\":{\"required_approving_review_count\":$approvals,
   \"dismiss_stale_reviews_on_push\":$owner_review,\"require_code_owner_review\":$owner_review,
   \"require_last_push_approval\":false,\"required_review_thread_resolution\":false}},
  {\"type\":\"non_fast_forward\"},{\"type\":\"deletion\"}$checks]}"
  echo "$body" | jq -e . >/dev/null || die "ruleset body is not valid JSON"
  # A merged branch is deleted at once; the PR keeps its commits, and the branch can be restored from it.
  gh api -X PATCH "repos/$nwo" -F delete_branch_on_merge=true --jq '"delete branch on merge: \(.delete_branch_on_merge)"' >&2
  id="$(gh api "repos/$nwo/rulesets" --jq ".[] | select(.name == \"$RULESET_NAME\") | .id")"
  if [ -n "$id" ]; then
    echo "$body" | gh api -X PUT "repos/$nwo/rulesets/$id" --input - >/dev/null
    say "ruleset $id updated on $nwo"
  else
    echo "$body" | gh api -X POST "repos/$nwo/rulesets" --input - >/dev/null
    say "ruleset created on $nwo"
  fi
}

interaction_limit() {
  local nwo="$1"
  gh api -X PUT "repos/$nwo/interaction-limits" \
    -f limit=collaborators_only -f expiry=six_months --jq '"limit \(.limit) until \(.expires_at)"'
}

secret_scanning() {
  local nwo="$1"
  gh api -X PATCH "repos/$nwo" --input - --jq '.security_and_analysis' <<'EOF'
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},
 "secret_scanning_push_protection":{"status":"enabled"}}}
EOF
}

# A project's Actions (step 4, plan decision 11): only GitHub-owned actions,
# pinned to a full SHA; a read-only GITHUB_TOKEN that cannot approve or create
# pull requests; approval for every outside contributor's run; and
# pull_request_target allowed for guards.yml only (GitHub blocks it on public
# repositories by default from 2026-12-02). The App cannot push workflow files.
GUARDS_POLICY_NAME="factory-guards-pull-request-target"
actions() {
  local nwo="$1" id body
  gh api -X PUT "repos/$nwo/actions/permissions" -F enabled=true -f allowed_actions=selected -F sha_pinning_required=true
  gh api -X PUT "repos/$nwo/actions/permissions/selected-actions" --input - <<'EOF'
{"github_owned_allowed":true,"verified_allowed":false,"patterns_allowed":[]}
EOF
  gh api -X PUT "repos/$nwo/actions/permissions/workflow" \
    -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
  gh api -X PUT "repos/$nwo/actions/permissions/fork-pr-contributor-approval" -f approval_policy=all_external_contributors
  body="$(cat <<EOF
{"name":"$GUARDS_POLICY_NAME","enforcement":"active",
 "conditions":{"workflow_path":{"include":[".github/workflows/guards.yml"],"exclude":[]}},
 "rules":[{"type":"restrict_action_events","parameters":{"allowed_events":["pull_request_target"]}}]}
EOF
)"
  id="$(gh api "repos/$nwo/actions/policies" --jq ".policies[] | select(.name == \"$GUARDS_POLICY_NAME\") | .id")"
  if [ -n "$id" ]; then
    echo "$body" | gh api -X PUT "repos/$nwo/actions/policies/$id" --input - >/dev/null
    say "policy $id updated on $nwo"
  else
    echo "$body" | gh api -X POST "repos/$nwo/actions/policies" --input - >/dev/null
    say "policy created on $nwo"
  fi
  status "$nwo"
}

# The factory repository runs no workflows.
actions_off() {
  local nwo="$1"
  gh api -X PUT "repos/$nwo/actions/permissions" -F enabled=false
  gh api "repos/$nwo/actions/permissions" --jq '"actions enabled: \(.enabled)"'
}

# Environment "preview" holds the Vercel secrets. Only main may deploy to it:
# preview-deploy runs on workflow_run, which uses main. The owner adds the
# secrets with gh secret set --env preview, so nobody else sees them.
preview_env() {
  local nwo="$1"
  gh api -X PUT "repos/$nwo/environments/preview" --input - >/dev/null <<'EOF'
{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
EOF
  if ! gh api "repos/$nwo/environments/preview/deployment-branch-policies" \
      --jq '.branch_policies[] | select(.name == "main" and .type == "branch")' | grep -q .; then
    gh api -X POST "repos/$nwo/environments/preview/deployment-branch-policies" -f name=main -f type=branch >/dev/null
  fi
  gh api "repos/$nwo/environments/preview/deployment-branch-policies" \
    --jq '"preview deploys from: \([.branch_policies[] | "\(.type):\(.name)"])"'
  gh api "repos/$nwo/environments/preview/secrets" --jq '"preview secrets: \([.secrets[].name])"'
}

code_scanning() {
  local nwo="$1"
  gh api -X PATCH "repos/$nwo/code-scanning/default-setup" -f state=configured -f query_suite=default
  gh api "repos/$nwo/code-scanning/default-setup" --jq '"code scanning: \(.state), languages \(.languages)"'
}

labels() {
  local nwo="$1" name color desc
  while IFS='|' read -r name color desc; do
    [ -n "$name" ] || continue
    gh label create "$name" --repo "$nwo" --color "$color" --description "$desc" --force
  done <<'EOF'
user-story|1d76db|Type: a user story for the factory
bug|d73a4a|Type: something is broken
chore|c5def5|Type: maintenance without user-visible change
trivial|bfdadc|Type: small change; light path skips spec review and acceptance tests
ready-for-factory|0e8a16|State: story is ready for the factory to pick up
needs-human|fbca04|State: waiting for the human (questions or approval)
spec-approved|5319e7|State: the human approved the spec
dispute|b60205|State: agents disagree; the human decides
tests-change-approved|f9d0c4|State: the human allows implementation to change acceptance tests
EOF
}

board() {
  local nwo="$1" owner repo number project_id
  owner="${nwo%%/*}"
  repo="${nwo##*/}"
  # Includes closed projects; an owner with more than 200 projects is not supported.
  number="$(gh project list --owner "$owner" --closed --limit 200 --format json \
    --jq ".projects[] | select(.title == \"$repo\") | .number")"
  [ "$(printf '%s\n' "$number" | grep -c .)" -le 1 ] || die "more than one project named '$repo': $(echo $number)"
  if [ -z "$number" ]; then
    number="$(gh project create --owner "$owner" --title "$repo" --format json --jq .number)"
    say "project $number created"
  else
    local closed
    closed="$(gh project view "$number" --owner "$owner" --format json --jq .closed)" \
      || die "cannot read project $number"
    case "$closed" in
      true) gh project close "$number" --owner "$owner" --undo >/dev/null; say "project $number was closed; reopened" ;;
      false) ;;
      *) die "unexpected closed state for project $number: '$closed'" ;;
    esac
  fi
  local link_out
  if ! link_out="$(gh project link "$number" --owner "$owner" --repo "$nwo" 2>&1)"; then
    echo "$link_out" | grep -qi "already" || die "cannot link project $number to $nwo: $link_out"
  fi
  project_id="$(gh project view "$number" --owner "$owner" --format json --jq .id)"

  local views name filter view_id
  # Board shows issues only: a story is an issue and its PR is linked to it.
  # Filters are (re)applied on every run, so this also fixes existing views.
  views="$(gh api graphql -f id="$project_id" -f query='
    query($id: ID!) { node(id: $id) { ... on ProjectV2 { views(first: 50) { nodes { id name } } } } }' \
    --jq '.data.node.views.nodes[] | "\(.name)|\(.id)"')"
  while IFS='|' read -r name filter; do
    [ -n "$name" ] || continue
    view_id="$(printf '%s\n' "$views" | awk -F'|' -v n="$name" '$1 == n {print $2; exit}')"
    if [ -z "$view_id" ]; then
      view_id="$(gh api graphql -f id="$project_id" -f name="$name" -f query='
        mutation($id: ID!, $name: String!) {
          createProjectV2View(input: {projectId: $id, name: $name, layout: TABLE_LAYOUT}) { projectV2View { id } } }' \
        --jq '.data.createProjectV2View.projectV2View.id')"
    fi
    gh api graphql -f id="$view_id" -f filter="$filter" -f query='
      mutation($id: ID!, $filter: String!) {
        updateProjectV2View(input: {viewId: $id, filter: $filter}) { projectV2View { name filter } } }' \
      --jq '.data.updateProjectV2View.projectV2View | "view \(.name): \(.filter)"'
  done <<'EOF'
Idea|is:issue is:open -label:ready-for-factory
Ready for factory|is:issue is:open label:ready-for-factory -label:spec-approved
Needs human|is:issue is:open label:needs-human
Dispute|is:issue is:open label:dispute
In progress|is:issue is:open label:spec-approved
Done|is:issue is:closed
EOF

  # GitHub creates an unfiltered default view; the factory views replace it.
  view_id="$(printf '%s\n' "$views" | awk -F'|' '$1 == "View 1" {print $2; exit}')"
  if [ -n "$view_id" ]; then
    gh api graphql -f id="$view_id" -f query='
      mutation($id: ID!) { deleteProjectV2View(input: {viewId: $id}) { clientMutationId } }' >/dev/null
    say "default view 'View 1' deleted"
  fi

  # Built-in workflows cannot be disabled through the API; report them.
  gh api graphql -f id="$project_id" -f query='
    query($id: ID!) { node(id: $id) { ... on ProjectV2 { workflows(first: 20) { nodes { name enabled } } } } }' \
    --jq '.data.node.workflows.nodes[] | select(.enabled) | "enabled workflow: \(.name)"' >&2 \
    || say "could not list project workflows"
  say "board: https://github.com/users/$owner/projects/$number"
  say "manual steps: auto-add rule with filter is:issue, and disable the Status workflows (see README)"
}

status() {
  local nwo="$1" id
  gh repo view "$nwo" --json visibility --jq '"visibility: \(.visibility)"'
  for id in $(gh api "repos/$nwo/rulesets" --jq '.[].id'); do
    gh api "repos/$nwo/rulesets/$id" --jq \
      '"ruleset \(.name): enforcement=\(.enforcement) bypass_actors=\([.bypass_actors[] | "\(.actor_type):\(.actor_id):\(.bypass_mode)"]) target=\(.conditions.ref_name.include) rules=\([.rules[].type])",
       (.rules[] | select(.type == "pull_request") | "  pull_request: \(.parameters | {required_approving_review_count, require_code_owner_review, dismiss_stale_reviews_on_push})"),
       (.rules[] | select(.type == "required_status_checks") | "  required checks: \([.parameters.required_status_checks[] | "\(.context)@\(.integration_id)"])"),
       (.rules[] | select(.type == "code_scanning") | "  code scanning: \(.parameters.code_scanning_tools)")'
  done
  gh api "repos/$nwo" --jq '"delete branch on merge: \(.delete_branch_on_merge)"'
  gh api "repos/$nwo/interaction-limits" --jq '"interaction limit: \(.limit // "none") until \(.expires_at // "-")"'
  gh api "repos/$nwo/actions/permissions" --jq '"actions: enabled=\(.enabled) allowed=\(.allowed_actions // "-") sha_pinning=\(.sha_pinning_required // "-")"'
  if [ "$(gh api "repos/$nwo/actions/permissions" --jq .enabled)" = "true" ]; then
    gh api "repos/$nwo/actions/permissions/selected-actions" --jq '"selected actions: github_owned=\(.github_owned_allowed) verified=\(.verified_allowed) patterns=\(.patterns_allowed)"'
    gh api "repos/$nwo/actions/permissions/workflow" --jq '"workflow token: \(.default_workflow_permissions), can approve PRs: \(.can_approve_pull_request_reviews)"'
    gh api "repos/$nwo/actions/permissions/fork-pr-contributor-approval" --jq '"fork PR approval: \(.approval_policy)"'
    gh api "repos/$nwo/actions/policies" --jq '.policies[] | "policy: \(.)"'
    gh api "repos/$nwo/actions/secrets" --jq '"repository secrets: \(.total_count)"'
  fi
  gh api "repos/$nwo" --jq '.security_and_analysis | "secret scanning: \(.secret_scanning.status), push protection: \(.secret_scanning_push_protection.status)"'
}

[ "$#" -ge 2 ] && { [ "$#" -eq 2 ] || [ "$1" = ruleset ]; } || die "usage: $0 <ruleset|interaction-limit|secret-scanning|actions|actions-off|code-scanning|preview-env|labels|board|status> <owner/repo>"
case "$1" in
  ruleset) ruleset "$2" "${3:-project}" ;;
  interaction-limit) interaction_limit "$2" ;;
  secret-scanning) secret_scanning "$2" ;;
  actions) actions "$2" ;;
  actions-off) actions_off "$2" ;;
  code-scanning) code_scanning "$2" ;;
  preview-env) preview_env "$2" ;;
  labels) labels "$2" ;;
  board) board "$2" ;;
  status) status "$2" ;;
  *) die "unknown subcommand: $1" ;;
esac
