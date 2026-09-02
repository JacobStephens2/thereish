#!/bin/zsh
# PROTOTYPE. Runs the Keeper bench on the VPS. Keys travel over ssh stdin into a mode-600 file that is deleted right
# after the run; nothing is ever put on a command line. Usage, from prototype/keeper/ with the keys in the environment:
#   rsync -a --delete --exclude deps --exclude _build --exclude .git --exclude results --exclude 'PROTOTYPE-*' --exclude '*.env' ./ jacob@stephens.page:~/keeper-proto/
#   ssh jacob@stephens.page 'cd ~/keeper-proto && docker build -q -t keeper-proto .'
#   LABEL=vps-3 BENCH_ARGS="--candidates kimi_max,kimi_low --label vps-3" tools/run-vps.sh
set -e
S="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="${LABEL:-vps}"
BENCH_ARGS="${BENCH_ARGS:---label vps}"
umask 077
printf 'ANTHROPIC_API_KEY=%s\nOPENAI_API_KEY=%s\nBASETEN_API_KEY=%s\nGEMINI_API_KEY=%s\nFIREWORKS_API_KEY=%s\n' "$ANTHROPIC_API_KEY" "$OPENAI_API_KEY" "$BASETEN_API_KEY" "$GEMINI_API_KEY" "$FIREWORKS_API_KEY" > "$S/PROTOTYPE-keeper.env"
ssh jacob@stephens.page 'umask 077; cat > ~/keeper.env; chmod 600 ~/keeper.env; ls -l ~/keeper.env' < "$S/PROTOTYPE-keeper.env"
rm -f "$S/PROTOTYPE-keeper.env"
ssh jacob@stephens.page 'mkdir -p ~/keeper-results && chmod 777 ~/keeper-results; set +e; docker run --rm --env-file ~/keeper.env -v ~/keeper-results:/app/results keeper-proto keeper.bench --n 20 '"$BENCH_ARGS"'; code=$?; rm -f ~/keeper.env; echo "container exit $code; env file removed: $(ls ~/keeper.env 2>&1)"'
scp -q jacob@stephens.page:~/keeper-results/bench-$LABEL.md jacob@stephens.page:~/keeper-results/bench-$LABEL.json "$S/results/"
ls -l "$S/results/bench-$LABEL."*
