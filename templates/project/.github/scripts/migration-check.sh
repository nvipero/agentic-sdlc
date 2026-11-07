#!/usr/bin/env bash
# Migration changes in one database component's directory between two commits,
# for the guards (factory docs/gates.md) and for /factory:run's implementation
# checks. Postgres SQL, whichever host runs it. Reads git objects only; runs
# nothing from the repository.
#
#   migration-check.sh <base> <head> <dir>
#
# Prints one line per finding:
#   approval: <why>   needs the owner's migration-approved label on the issue
#   look: <what>      for the reviewer's "Where to look"
# Exits 1 if any line is an approval, 0 otherwise.
#
# Approval: an existing migration changed, renamed or removed (one on main is
# applied, or will be at deploy); an added migration with a destructive or
# authorisation-weakening statement. Approval is matched on the raw SQL, comments
# included, so a "--" inside a string cannot hide the rest of a line: a comment
# that names a drop costs a label. It is still a heuristic: SQL built at run time
# (execute format(...)) is not seen (docs/risks.md).
set -euo pipefail

base="${1:?base commit}" head="${2:?head commit}" dir="${3:?migrations directory}"
need=0

# classify <path>: "approval <statement>" and "look <statement>" lines for an added
# SQL file, lowercase and whitespace collapsed; look lines without comments.
classify() {
  git show "$head:$1" | perl -0777 -ne '
    $_ = lc; my $raw = $_;
    $raw =~ s{\s+}{ }g;
    for my $s (split /;/, $raw) {
      $s =~ s/^ +| +$//g;
      print "approval ", substr($s, 0, 160), "\n"
        if $s =~ /\bdrop\b(?! (default|not null|identity|expression|index)\b)|\btruncate\b|\bdelete from\b|\brename\b|\balter (column )?("[^"]*"|[a-z0-9_]+) (set data )?type\b|\bdisable row level security\b/;
    }
    s{/\*.*?\*/}{ }gs; s{--[^\n]*}{}g; s{\s+}{ }g;
    for my $s (split /;/) {
      $s =~ s/^ +| +$//g;
      print "look ", substr($s, 0, 160), "\n"
        if $s =~ /\bgrant\b|\brevoke\b|\bcreate policy\b|\balter policy\b|\bsecurity definer\b|\bcron\.schedule\b|\bnet\.http_/;
    }'
}

# NUL-separated, so no path is quoted: status, path, and for a rename or copy the new path.
while IFS= read -r -d '' status; do
  IFS= read -r -d '' path
  new=
  case "$status" in R*|C*) IFS= read -r -d '' new ;; esac
  case "$status" in
    A)
      case "$path" in
        *.sql) ;;
        *) echo "look: non-SQL file in the migrations: \`$path\`"; continue ;;
      esac
      echo "look: new migration \`$path\`"
      out="$(classify "$path")" || { echo "approval: cannot read \`$path\`"; need=1; continue; }
      while read -r kind s; do
        [ -n "$kind" ] || continue
        echo "$kind: \`$path\`: $s"
        if [ "$kind" = approval ]; then need=1; fi
      done <<<"$out"
      ;;
    R*|C*) echo "approval: existing migration \`$path\` renamed or copied to \`$new\`"; need=1 ;;
    D) echo "approval: existing migration \`$path\` removed"; need=1 ;;
    *) echo "approval: existing migration \`$path\` changed ($status)"; need=1 ;;
  esac
done < <(git diff --name-status -M -z "$base...$head" -- "$dir")

exit "$need"
