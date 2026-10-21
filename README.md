# Forever Cult Fund (FOREVER)

A fixed-supply ERC-20 for Ethereum. The deployable contract is
[`ForeverToken`](src/ForeverToken.sol), built with Solidity **0.8.26** and
OpenZeppelin Contracts **v5.1.0**.

| Parameter | Value |
| --- | --- |
| Token name | Forever Cult Fund |
| Token symbol | FOREVER |
| Decimals | 18 |
| Supply in whole tokens | 1,000,000,000 |
| Supply in smallest units | 1000000000000000000000000000 (10^27) |
| Constructor arguments | None (`[]`) |
| Initial recipient | `msg.sender`, the immediate deploying account or contract |
| Solidity artifact | `src/ForeverToken.sol:ForeverToken` |
| Application contracts | None |

## Behavior and assumptions

The constructor mints the entire supply once and emits the standard
`Transfer(address(0), deployer, supply)` event. There is no externally callable
mint or burn function. Transfers preserve the supply and deliver the exact
requested amount. The brief specifies no additional transfer rules, so the token
uses ordinary ERC-20 behavior without taxes, transfer limits, vesting, rebasing,
pausing, blacklisting, or privileged balance changes.

There is no owner, administrator, proxy, upgrade mechanism, initializer, oracle,
external contract dependency, or post-deployment configuration. The token does
not make external calls, including calls to transfer recipients. It does not
manage a fund or promise returns; its name is token metadata.

`transfer`, `approve`, and `transferFrom` return `true` on success. Invalid
operations revert with OpenZeppelin's ERC-6093 custom errors. Transfers to the
zero address and approvals to the zero spender revert. Zero-value transfers
between valid addresses are allowed and emit `Transfer`; self-transfers preserve
balances. `approve` replaces the existing allowance and emits `Approval`.
Finite allowances decrease on `transferFrom`, including self-transfers;
`type(uint256).max` is treated as unlimited and remains unchanged. Consuming an
allowance does not emit another `Approval` event in this OpenZeppelin version.
Reverts leave both balances and allowances unchanged.

## Build and check

From the repository root, with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x89b895d8724663244b2e17b4fc9cc93e5df26aaa7b70bf3573606b1e3b35a605 forge test
forge fmt --check
```

The compiler is version-pinned in `foundry.toml`, targets Cancun, and uses the
optimizer with 200 runs. `bytecode_hash = "none"` disables the metadata hash.
No compiler binary is included. All Solidity dependencies and licenses are
ordinary files under `lib/`, so no network, package installation, submodules,
environment-based test configuration, RPC endpoint, or filesystem cheatcodes
are needed. FFI and filesystem permissions are not enabled.

Tests include metadata and constructor minting, CREATE2 factory deployment,
exact distribution and claim transfers, events, boundary amounts, allowance
consumption and revocation, failed-operation rollback, zero-address rejection,
and rejected mint/admin calls. Four fuzz tests run 1,024 cases each. Two stateful
invariants run 256 sequences of up to 64 operations each, comparing all balances
and allowances against an independent model and checking conservation of supply.
Tests reset their own state and do not depend on execution order or test sender
environment variables. The distribution test models token movements only;
the network's protected launch harness performs the actual Uniswap v4 pool and
swap integration checks separately.

Local validation passed with Solidity 0.8.26: `forge build`, the seeded
`forge test` command above, and `forge fmt --check`. The test run passed all 32
unit/fuzz tests and both invariant properties across 16,384 stateful calls with
zero reverts. The compiled token has 1,752 bytes of runtime code and no external
library link references. Every vendored file was checked against its recorded
SHA-256 hash.

## Deployment

The launch service deploys `ForeverToken` directly from its compiled creation
bytecode on Ethereum (chain ID 1), with no constructor arguments or ETH value.
The constructor makes no external calls and works on an otherwise empty chain.
When a factory deploys the token, **the factory receives all 10^27 units**;
the transaction origin and the account invoking that factory receive none from
the constructor. A direct deployment instead gives the entire supply to its
direct deployer. Choose the intended deployment path accordingly.

The launch factory is responsible for distribution: 10% to the launch's
MerkleDistributor, 80% to pool seeding, and the remaining 10% to the requester
under the supplied launch policy. These allocations are handled outside the
token. No addresses or launch infrastructure are embedded in the contract, and
none of the supply is reserved for an application contract. The separate launch
manifest step records the artifact, metadata, exact supply, pool settings, and
requester economics; this project does not create a `launch.json`.

The launch operator must verify the built artifact and compiler settings, then
check the deployment's metadata, total supply, factory balance, and subsequent
distribution receipts. Source verification and deployment transactions belong
to that operator. This repository does not broadcast transactions or require a
wallet key or signer configuration.

## After launch

There are no owner setters, administrative duties, scheduled calls, or settings
to initialize. Holders control transfers and spender approvals. Approve only
trusted spenders and the amounts needed; unlimited approval remains usable until
revoked. When changing an existing nonzero allowance, consider first setting it
to zero and confirming that transaction to limit the standard ERC-20 allowance
replacement race.

Recipients must be checked carefully. Transfers to contracts do not invoke a
receiver callback. Tokens sent to this token's own address or a contract without
a withdrawal path may be permanently inaccessible. There is no rescue function.
Ordinary ETH sends revert; forcibly sent ETH and unrelated tokens cannot be
recovered by an administrator. No party can pause or upgrade this deployment to
correct mistakes.

## Dependencies and review

- OpenZeppelin Contracts v5.1.0: the unmodified ERC-20 implementation, its four
  required Solidity imports, and MIT license are vendored under
  `lib/openzeppelin-contracts/`.
- Forge Standard Library v1.9.7: Solidity test utilities and both upstream
  licenses are vendored under `lib/forge-std/`.
- [`lib/dependencies.json`](lib/dependencies.json) records the upstream release
  archive URLs, archive SHA-256 hashes, and hashes of every vendored file.

The supplied security reference was reviewed for access control, supply math,
allowance authorization, failure atomicity, input validation, and external-call
risks. Production code adds only the fixed metadata and constructor mint to
OpenZeppelin ERC-20. No trading, oracle, signature, callback, or upgrade logic is
introduced. Local validation uses Foundry compilation, unit tests, fuzzing,
stateful invariants, and formatting checks. Slither and Mythril were not run.
These checks are not an independent audit; independent adversarial review and
post-deployment verification remain release responsibilities.
