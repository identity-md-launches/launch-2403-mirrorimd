# MirrorIMD (MIRROR)

MirrorIMD is an immutable, fixed-supply ERC-20 implemented in
[`src/MirrorIMD.sol`](src/MirrorIMD.sol) using vendored OpenZeppelin Contracts v5.0.2.

| Parameter | Value |
| --- | --- |
| Solidity contract | `MirrorIMD` |
| Token name | `MirrorIMD` |
| Symbol | `MIRROR` |
| Decimals | `18` |
| Supply | `1,000,000,000` MIRROR |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor value | `0` ETH |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |

The constructor makes exactly one mint and emits
`Transfer(address(0), msg.sender, INITIAL_SUPPLY)`. There is no public mint or burn
function and no owner, roles, pause, blacklist, transfer tax, rebase, proxy, or
upgrade mechanism. Transfers deliver the exact amount requested. No additional
application contract is required.

## Build and test

Run from the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xb3182e0eeaca4a0016805ee76d1e03f440ee47c8db640f2a45f42ee0cfb85040 forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM, optimizer enabled with 200
runs, and `bytecode_hash = "none"`. Cancun support is an assumption of the
deployment chain; the intended Ethereum launch supports it. No FFI or filesystem
permissions are enabled. All Solidity imports are ordinary files in this
repository. Building and testing need no RPC or dependency download; Foundry and
the pinned compiler must already be available to an offline verifier.

Tests cover constructor metadata, the exact supply and mint event, deployment
through a factory, exact distribution and claim transfers, transfer and approval
events, full-supply/single-unit/zero/self transfers, finite and unlimited
allowances, revocation, spender isolation, and rejection of invalid addresses,
insufficient balances, insufficient allowances, and unsupported mint/admin calls.
Failed delegated transfers must roll back allowance changes. Four fuzz tests
exercise success and failure accounting, with 1,024 cases each. Two stateful
invariants exercise randomized sequences of direct transfers, approvals,
delegated transfers, and rejected overdrafts across four holders, checking
conservation and allowance accounting (128 runs, depth 64).

The factory fixture tests token distribution mechanics locally. It does not
simulate Uniswap or replace the network's separate protected launch checks.

## Deployment and assumptions

Deploy the creation bytecode for `src/MirrorIMD.sol:MirrorIMD` directly, with no
arguments, linked libraries, external-contract prerequisites, or initialization
call. The constructor performs no external calls. The contract is intended for
direct deployment, not deployment behind a proxy.

In the intended factory launch, the factory is `msg.sender` and receives all
`10^27` base units. The external caller of that factory receives nothing from the
constructor. The factory is responsible for distributing the entire supply under
the launch policy: 10% to the swarm distributor, 80% to pool seeding, and the
remaining 10% to the requester's designated recipient. These are factory
operations; the token constructor does not allocate or reserve any balance for
other addresses. Direct deployment by an account instead credits that account.
The deployer receives no continuing authority over other holders.

The network's subsequent manifest step supplies the factory, pool, recipient,
and launch economics; those are not token constructor parameters. This project
does not create a launch manifest or execute transactions.

## After launch

There are no administrative setters, ownership handoffs, oracle subscriptions,
keepers, or other token settings. The launch operator is responsible for:

- Deploying the reviewed bytecode and recording the resulting token address.
- Confirming the metadata, total supply, constructor mint recipient, and factory
  distributions against the accepted launch configuration.
- Publishing/verifying the source with the exact compiler and build settings.
- Completing the network's independent adversarial review before release.

Holders control transfers and spender approvals. Zero-value transfers to nonzero
addresses are supported, including from an empty balance. Transfers to the zero
address and approvals to a zero spender revert. A finite allowance is consumed
by `transferFrom`; an allowance of `type(uint256).max` retains OpenZeppelin's
unlimited-approval behavior. A holder using `transferFrom` on their own balance
still needs an allowance; `transfer` does not.

Approve only what a spender needs. To replace an existing nonzero approval,
revoke it first and confirm the revocation before setting the new value; this
reduces the standard ERC-20 allowance replacement race. `Approval` is emitted by
`approve`; OpenZeppelin v5 does not emit another `Approval` when `transferFrom`
spends an allowance, so integrations should query `allowance` for current state.

The token makes no callbacks to recipients or external contracts. ERC-20
transfers do not verify that a recipient can return tokens. Assets sent to the
token contract or to an incompatible recipient can be permanently inaccessible;
there is no recovery administrator. Plain ETH transfers revert because the
contract has no payable receive or fallback function.

## Security and dependencies

The security review considered the supplied checklist: the token has no external
interactions, privileged entry points, arithmetic involving prices, signatures,
proxies, or delegatecalls. Checked address/balance/allowance validation and
standard events come from the unchanged ERC-20 implementation. Its unchecked
balance arithmetic relies on supply conservation and prior balance checks.
Only the constructor calls `_mint`; `_burn` is not exposed.

Local verification uses Foundry unit, fuzz, and stateful invariant tests, plus
build and formatting checks. Slither and Mythril were not run. These checks do
not constitute an independent audit; on-chain verification and launch integration
remain the launch operator's responsibilities.

The minimal OpenZeppelin dependency subset and its MIT license are in
[`lib/openzeppelin-contracts`](lib/openzeppelin-contracts). See
[`DEPENDENCIES.md`](DEPENDENCIES.md) for provenance. Project-authored source and
tests are MIT licensed; see [`LICENSE`](LICENSE).
