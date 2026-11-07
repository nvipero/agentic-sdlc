#!/usr/bin/env bash
# Supabase changes between two commits, for the guards (factory docs/gates.md) and
# for /factory:run's implementation checks. Reads git objects only; runs nothing
# from the repository.
#
#   supabase-check.sh <base> <head>
#
# Prints one line per finding:
#   approval: <why>   needs the owner's migration-approved label on the issue
#   look: <what>      for the reviewer's "Where to look"
# Exits 1 if any line is an approval, 0 otherwise.
#
# Approval: an existing migration changed, renamed or removed (one on main is
# applied, or will be at deploy); an added migration with a destructive or
# authorisation-weakening statement. Matched on the SQL with comments removed:
# a heuristic, so dynamic SQL inside a do block is not seen (docs/risks.md).
set -euo pipefail

base="${1:?base commit}" head="${2:?head commit}"
need=0

# classify <path>: prints "approval|look <statement>" for the added SQL file's
# statements that match, with comments removed, lowercase, whitespace collapsed.
classify() {
  git show "$head:$1" | perl -0777 -ne '
    s{/\*.*?\*/}{ }gs; s{--[^\n]*}{}g; $_ = lc; s{\s+}{ }g;
    for my $s (split /;/) {
      $s =~ s/^ +| +$//g; next unless length $s;
      if ($s =~ /\bdrop (table|column|schema|type|view|materialized view|function|policy)\b|\btruncate\b|\bdelete from\b|\balter column [a-z0-9_"]+ (set data )?type\b|\brename (to|column)\b|\bdisable row level security\b/) {
        print "approval ", substr($s, 0, 160), "\n";
      } elsif ($s =~ /\bgrant\b|\brevoke\b|\bcreate policy\b|\balter policy\b|\bsecurity definer\b|\bcron\.schedule\b|\bnet\.http_/) {
        print "look ", substr($s, 0, 160), "\n";
      }
    }'
}

while IFS=$'\t' read -r status path rest; do
  case "$status" in
    A)
      case "$path" in *.sql) ;; *) continue ;; esac
      echo "look: new migration \`$path\`"
      while read -r kind s; do
        echo "$kind: \`$path\`: $s"
        if [ "$kind" = approval ]; then need=1; fi
      done < <(classify "$path")
      ;;
    R*) echo "approval: existing migration \`$path\` renamed to \`$rest\`"; need=1 ;;
    D) echo "approval: existing migration \`$path\` removed"; need=1 ;;
    *) echo "approval: existing migration \`$path\` changed"; need=1 ;;
  esac
done < <(git diff --name-status -M "$base...$head" -- supabase/migrations)

while IFS= read -r line; do
  echo "look: \`supabase/config.toml\`: ${line:0:160}"
done < <(git diff -U0 "$base...$head" -- supabase/config.toml | grep -E '^[+-][^+-]' || true)

exit "$need"
