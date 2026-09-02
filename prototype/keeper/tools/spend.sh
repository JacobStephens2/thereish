#!/bin/zsh
# Spend table from per-call log lines only (Mac PROTOTYPE-calls.log + VPS run logs). Prints markdown.
cd "$(dirname "$0")/.."
R=results
{ awk '/^[0-9T:.Z-]+ \[/ {print "mac", $3, $0}' PROTOTYPE-calls.log; awk '/^\[assayer\]/ {print "vps", $2, $0}' $R/vps-run*.txt; } | awk '{
  where=$1; m=$2; for(i=1;i<=NF;i++) if($i ~ /^\$/) c=substr($i,2); k[m]++; s[m]+=c; t+=c; n++; kw[where]++; sw[where]+=c }
  END { printf "| model | calls | logged $ |\n|---|---|---|\n"; for (m in s) if (m!="fake") printf "| %s | %d | %.4f |\n", m, k[m], s[m]; printf "| **total logged** | %d | **%.4f** |\n", n, t; printf "\nMac %d calls $%.4f; VPS %d calls $%.4f\n", kw["mac"], sw["mac"], kw["vps"], sw["vps"] }' | sort -t'|' -k4 -r
