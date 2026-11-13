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
# Exits 0 when the check ran, whatever it found; any other exit is an error, never
# a result.
#
# Look also covers what changes a migration's deploy: a statement PostgreSQL runs
# outside a transaction (concurrently, vacuum, cluster, alter system), the file's
# own transaction control (begin, commit, rollback), and the
# pg-delta transaction=false directive (factory docs/setup.md, "Supabase production").
#
# Approval: an existing migration changed, renamed or removed (one on main is
# applied, or will be at deploy); an added migration with a destructive or
# authorisation-weakening statement. Approval is matched on the raw SQL, comments
# included, so a "--" inside a string cannot hide the rest of a line (a comment
# that names a drop costs a label), and again without comments, so a comment
# inside a statement (delete /* x */ from) cannot split it. It is still a heuristic: SQL built at run time
# (execute format(...)) is not seen (docs/risks.md).
set -euo pipefail

base="${1:?base commit}" head="${2:?head commit}" dir="${3:?migrations directory}"
changes="$(mktemp)"
trap 'rm -f "$changes"' EXIT
git diff --name-status -M -z "$base...$head" -- "$dir" > "$changes"

# classify <path>: "approval <statement>" and "look <statement>" lines for an added
# SQL file, lowercase and whitespace collapsed; look lines without comments.
classify() {
  git show "$head:$1" | perl -0777 -ne '
    $_ = lc; my $raw = $_;
    my $approval = qr/\bdrop\b(?! (default|not null|identity|expression|index)\b)|\btruncate\b|\bdelete from\b|\brename\b|\balter (column )?("[^"]*"|[a-z0-9_]+) (set data )?type\b|\bdisable row level security\b/;
    my %seen;
    $raw =~ s{\s+}{ }g;
    for my $s (split /;/, $raw) {
      $s =~ s/^ +| +$//g;
      print "approval ", substr($s, 0, 160), "\n" if $s =~ $approval && !$seen{$s}++;
    }
    s{/\*.*?\*/}{ }gs; s{--[^\n]*}{}g; s{\s+}{ }g;
    for my $s (split /;/) {
      $s =~ s/^ +| +$//g;
      print "approval ", substr($s, 0, 160), "\n" if $s =~ $approval && !$seen{$s}++;
      print "look ", substr($s, 0, 160), "\n"
        if $s =~ /\bgrant\b|\brevoke\b|\bcreate policy\b|\balter policy\b|\bsecurity definer\b|\bowner to\b|\bcron\.schedule\b|\bnet\.http_|\bvault\.|\bconcurrently\b|^(vacuum|cluster|alter system)\b|^(begin|commit|start transaction|abort|rollback|prepare transaction)\b/;
    }
    # Runs outside the one transaction a file gets at deploy, so a failure is not rolled back.
    print "look pg-delta: transaction=false (no rollback at deploy)\n" if $raw =~ /--\s*pg-delta:\s*transaction=false/;'
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
      out="$(classify "$path")" || { echo "approval: cannot read \`$path\`"; continue; }
      while read -r kind s; do
        [ -n "$kind" ] || continue
        echo "$kind: \`$path\`: $s"
      done <<<"$out"
      ;;
    R*|C*) echo "approval: existing migration \`$path\` renamed or copied to \`$new\`" ;;
    D) echo "approval: existing migration \`$path\` removed" ;;
    *) echo "approval: existing migration \`$path\` changed ($status)" ;;
  esac
done < "$changes"
