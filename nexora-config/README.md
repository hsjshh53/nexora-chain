# NEXORA local devnet

NEXORA uses the Cosmos EVM application in `evm/evmd` as its execution and
consensus application. The local setup gives it a dedicated chain ID, NEX
denomination, node home, and RPC ports without changing the existing Cosmos EVM
checkout or the separately running `evmd` node.

## Why NEXORA uses a separate port range

The existing `evmd` process in this workspace is listening on CometBFT P2P
`26656`, CometBFT RPC `26657`, and EVM JSON-RPC `8545`/WebSocket `8546`. Starting
another node on those defaults would fail with an address-in-use error. NEXORA
keeps the existing node untouched and binds its local-only services separately:
optional CometBFT pprof is disabled in this devnet to avoid the default `6060`
listener as well.

| Service | NEXORA address |
| --- | --- |
| CometBFT RPC | `127.0.0.1:27657` |
| CometBFT P2P | `127.0.0.1:27656` |
| EVM JSON-RPC HTTP | `127.0.0.1:28545` |
| EVM JSON-RPC WebSocket | `127.0.0.1:28546` |
| Cosmos gRPC | `localhost:29090` |

These are development bindings, not production validator or public-RPC
settings.

## Build and initialize

The `evm/` directory is an existing Cosmos EVM checkout and is intentionally
left unmodified. Build the NEXORA-compatible executable from its `evmd` app:

```sh
bash nexora-config/localnet.sh build
```

The default executable path is `~/.local/bin/nexorad`. Initialize a fresh local
chain and a single validator:

```sh
bash nexora-config/localnet.sh init
```

Initialization uses a separate `~/.nexora` home, chain ID `nexora_9002-1`,
EVM chain ID `9002`, and base denomination `anex` (display denomination `NEX`,
18 decimals). It creates a disposable test key named `validator` and funds the
local genesis account with 1,000,000 NEX. The script refuses to initialize over
a non-empty home.

To use a different executable or home, set `NEXORA_BINARY` and/or `NEXORA_HOME`
when invoking the script. For example:

```sh
NEXORA_HOME="$HOME/.nexora-dev" bash nexora-config/localnet.sh init
```

## Start the chain

Run the node in the foreground:

```sh
bash nexora-config/localnet.sh start
```

Check the CometBFT status and EVM JSON-RPC:

```sh
curl http://127.0.0.1:27657/status
curl -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://127.0.0.1:28545
```

The JSON-RPC chain ID should be `0x232a` (9002).

## Connect MetaMask

In MetaMask, open the network selector, choose **Add network** then **Add a
network manually**, and enter:

| Setting | Value |
| --- | --- |
| Network name | `NEXORA Local Devnet` |
| Default RPC URL | `http://127.0.0.1:28545` |
| Chain ID | `9002` (or `0x232a`) |
| Currency symbol | `NEX` |
| Block explorer URL | Leave blank |

Save the network and switch to it. If you are using VS Code in a remote
container/Codespace, forward port `28545` from the **Ports** view and use its
forwarded HTTPS address for the RPC URL; `127.0.0.1` in MetaMask means your
browser's machine, not the remote container. Keep the forwarded port private.

The validator account funded at genesis is a disposable local development
account. To import it into MetaMask, print its private key in your local
terminal and enter it via **Account selector → Add account or hardware wallet
→ Import account**:

```sh
nexorad keys unsafe-export-eth-key validator --keyring-backend test --home ~/.nexora
```

The command displays an unencrypted private key. Never share it or use this
development account on a public network. If you used a non-default binary path,
replace `nexorad` with that binary's path.

To confirm the imported account is on NEXORA, check that MetaMask shows NEX and
the balance. For a direct RPC check, the funded validator's EVM balance can be
queried with `eth_getBalance`. A successful transfer should appear in the
activity list after it is included in a block.

## Solidity development

In [`nexora-core`](../nexora-core), run the existing in-memory tests with
`npm test`. To deploy to the local devnet, configure a funded, disposable
development account in Hardhat's keystore and run:

```sh
cd nexora-core
npx hardhat keystore set NEXORA_PRIVATE_KEY
npx hardhat ignition deploy --network nexora ignition/modules/Counter.ts
```

The Hardhat `nexora` network is configured to use `http://127.0.0.1:28545`.
