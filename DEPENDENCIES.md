# Vendored dependencies

The files under `lib/openzeppelin-contracts/` are copied verbatim from the
OpenZeppelin Contracts **v5.0.2** release:

https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2

Only this dependency closure is needed:

- `contracts/token/ERC20/ERC20.sol`
- `contracts/token/ERC20/IERC20.sol`
- `contracts/token/ERC20/extensions/IERC20Metadata.sol`
- `contracts/utils/Context.sol`
- `contracts/interfaces/draft-IERC6093.sol`
- `LICENSE`

The Solidity file headers record the last change to each file, which can predate
the release tag. Upstream files are unmodified. The remapping in `foundry.toml`
resolves `@openzeppelin/contracts/` into this directory. No package manager,
submodule, network access, or installation step is needed to use these files.

Tests use a small local interface to Foundry's built-in cheatcodes instead of an
external test framework dependency.
