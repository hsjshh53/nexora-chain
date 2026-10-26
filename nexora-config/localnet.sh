#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
EVM_APP_DIR="$REPO_ROOT/evm/evmd"
NEXORA_BINARY="${NEXORA_BINARY:-$HOME/.local/bin/nexorad}"
NEXORA_HOME="${NEXORA_HOME:-$HOME/.nexora}"
CHAIN_ID="nexora_9002-1"
EVM_CHAIN_ID="9002"
BASE_DENOM="anex"

usage() {
  cat <<'EOF'
Usage: localnet.sh <build|init|start>

Environment:
  NEXORA_BINARY  Binary path (default: ~/.local/bin/nexorad)
  NEXORA_HOME    Chain home (default: ~/.nexora)

Commands:
  build  Build the Cosmos EVM example app as the nexorad binary
  init   Initialize a new one-validator NEXORA devnet
  start  Start the initialized NEXORA devnet
EOF
}

die() {
  printf 'nexora: %s\n' "$*" >&2
  exit 1
}

require_binary() {
  [ -x "$NEXORA_BINARY" ] || die "binary not found or not executable: $NEXORA_BINARY (run 'localnet.sh build' first)"
}

run_quietly() {
  local output_file
  output_file="$(mktemp)"
  if "$@" >"$output_file" 2>&1; then
    rm -f "$output_file"
  else
    cat "$output_file" >&2
    rm -f "$output_file"
    return 1
  fi
}

build() {
  command -v go >/dev/null 2>&1 || die "Go is required to build the Cosmos EVM app"
  [ -f "$EVM_APP_DIR/go.mod" ] || die "Cosmos EVM app source is missing: $EVM_APP_DIR"
  mkdir -p "$(dirname "$NEXORA_BINARY")"
  (cd "$EVM_APP_DIR" && go build -trimpath -ldflags="-s -w" -o "$NEXORA_BINARY" ./cmd/evmd)
  printf 'Built NEXORA-compatible Cosmos EVM binary at %s\n' "$NEXORA_BINARY"
}

configure_toml() {
  python3 - "$NEXORA_HOME" "$CHAIN_ID" "$EVM_CHAIN_ID" <<'PY'
import json
import re
import sys
from pathlib import Path

home = Path(sys.argv[1])
chain_id = sys.argv[2]
evm_chain_id = int(sys.argv[3])

def set_values(path, changes):
    lines = path.read_text().splitlines(keepends=True)
    section = ""
    found = {key: 0 for key in changes}

    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped[1:-1]
            continue

        key = (section, re.match(r"\s*([A-Za-z0-9_-]+)\s*=", line).group(1)
               if re.match(r"\s*([A-Za-z0-9_-]+)\s*=", line) else None)
        if key not in changes:
            continue

        value = changes[key]
        encoded = json.dumps(value) if isinstance(value, str) else str(value).lower()
        prefix = re.match(r"^(\s*[A-Za-z0-9_-]+\s*=\s*)", line).group(1)
        ending = "\n" if line.endswith("\n") else ""
        lines[index] = f"{prefix}{encoded}{ending}"
        found[key] += 1

    missing = [f"[{section}] {key}" for (section, key), count in found.items() if count != 1]
    if missing:
        raise SystemExit(f"Expected exactly one setting for {', '.join(missing)} in {path}")
    path.write_text("".join(lines))

config_dir = home / "config"
set_values(config_dir / "config.toml", {
    ("rpc", "pprof_laddr"): "",
    ("rpc", "laddr"): "tcp://127.0.0.1:27657",
    ("p2p", "laddr"): "tcp://127.0.0.1:27656",
    ("mempool", "type"): "app",
})
set_values(config_dir / "app.toml", {
    ("", "minimum-gas-prices"): "0anex",
    ("grpc", "address"): "localhost:29090",
    ("evm", "evm-chain-id"): evm_chain_id,
    ("json-rpc", "enable"): True,
    ("json-rpc", "address"): "127.0.0.1:28545",
    ("json-rpc", "ws-address"): "127.0.0.1:28546",
})
set_values(config_dir / "client.toml", {
    ("", "chain-id"): chain_id,
    ("", "keyring-backend"): "test",
    ("", "node"): "tcp://127.0.0.1:27657",
})
PY
}

init() {
  require_binary
  command -v jq >/dev/null 2>&1 || die "jq is required to set NEXORA token metadata"
  command -v python3 >/dev/null 2>&1 || die "Python 3 is required to configure the generated TOML files"

  if [ -d "$NEXORA_HOME" ] && [ -n "$(find "$NEXORA_HOME" -mindepth 1 -print -quit)" ]; then
    die "refusing to overwrite non-empty chain home: $NEXORA_HOME"
  fi

  mkdir -p "$NEXORA_HOME"
  run_quietly "$NEXORA_BINARY" init nexora-local \
    --chain-id "$CHAIN_ID" \
    --default-denom "$BASE_DENOM" \
    --home "$NEXORA_HOME"

  run_quietly "$NEXORA_BINARY" keys add validator --keyring-backend test --home "$NEXORA_HOME"
  run_quietly "$NEXORA_BINARY" genesis add-genesis-account validator \
    1000000000000000000000000"$BASE_DENOM" \
    --keyring-backend test \
    --home "$NEXORA_HOME"
  run_quietly "$NEXORA_BINARY" genesis gentx validator \
    1000000000000000000000"$BASE_DENOM" \
    --chain-id "$CHAIN_ID" \
    --keyring-backend test \
    --home "$NEXORA_HOME"
  run_quietly "$NEXORA_BINARY" genesis collect-gentxs --home "$NEXORA_HOME"

  genesis="$NEXORA_HOME/config/genesis.json"
  temporary_genesis="$(mktemp "$NEXORA_HOME/config/genesis.json.XXXXXX")"
  jq '
    .app_state.bank.denom_metadata =
      ((.app_state.bank.denom_metadata // [])
        | map(select(.base != "anex"))
        + [{
          description: "NEXORA native token",
          denom_units: [
            {denom: "anex", exponent: 0},
            {denom: "NEX", exponent: 18, aliases: ["nex"]}
          ],
          base: "anex",
          display: "NEX",
          name: "NEXORA",
          symbol: "NEX"
        }])
  ' "$genesis" > "$temporary_genesis"
  mv "$temporary_genesis" "$genesis"

  configure_toml
  printf 'Initialized NEXORA chain %s in %s\n' "$CHAIN_ID" "$NEXORA_HOME"
}

start() {
  require_binary
  [ -f "$NEXORA_HOME/config/genesis.json" ] || die "chain is not initialized; run 'localnet.sh init' first"
  exec "$NEXORA_BINARY" start --home "$NEXORA_HOME" "$@"
}

command="${1:-help}"
if [ "$#" -gt 0 ]; then
  shift
fi

case "$command" in
  build) build ;;
  init) init ;;
  start) start "$@" ;;
  help|-h|--help) usage ;;
  *) usage >&2; die "unknown command: $command" ;;
esac
