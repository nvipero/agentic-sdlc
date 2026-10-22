#!/usr/bin/env bash
# Redacts host-identifying details from exit check output before it is
# published. Reads stdin, writes stdout. Review the result anyway.
#
#   scripts/redact.sh < raw.txt > redacted.txt
set -euo pipefail

REDACT_HOME="$HOME" REDACT_USER="$(id -un)" REDACT_HOST="$(hostname -s)" perl -pe '
  BEGIN { ($h, $u, $n) = map { quotemeta } @ENV{qw(REDACT_HOME REDACT_USER REDACT_HOST)}; }
  s#$h#~#g;
  s#/Users/$u#~#g;
  s#\b$u\b#<user>#gi;
  s#\b$n\b#<host>#gi;
  s#[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}#<email>#g;
  s#\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b#<private-ip>#g;
  s#\b192\.168\.\d{1,3}\.\d{1,3}\b#<private-ip>#g;
  s#\b169\.254\.\d{1,3}\.\d{1,3}\b#<private-ip>#g;
  s#\b172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}\b#($& eq "172.17.0.1") ? $& : "<private-ip>"#ge;
'
