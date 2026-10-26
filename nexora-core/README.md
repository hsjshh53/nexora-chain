# NEXORA Core

This Hardhat 3 project is the Solidity application workspace for NEXORA Chain.
It includes a sample `Counter` contract and tests that run against Hardhat's
in-memory EVM.

## Build and test

From this directory:

```sh
npm run build
npm test
```

## Connect to the local NEXORA devnet

Start the local Cosmos EVM chain using the steps in
[`nexora-config/README.md`](../nexora-config/README.md). NEXORA's local EVM JSON-RPC
endpoint is `http://127.0.0.1:28545`, with EVM chain ID `9002`.

The initialized local validator is funded with test NEX. Export its EVM key
only for local development (the output is an unencrypted private key):

```sh
nexorad keys unsafe-export-eth-key validator --keyring-backend test --home ~/.nexora
```

Store that output in Hardhat's local keystore:

```sh
npx hardhat keystore set NEXORA_PRIVATE_KEY
```

Then deploy the sample contract:

```sh
npx hardhat ignition deploy --network nexora ignition/modules/Counter.ts
```

Use only disposable development keys on a local devnet.
