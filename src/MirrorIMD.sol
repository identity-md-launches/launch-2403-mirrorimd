// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MirrorIMD
/// @notice Fixed-supply ERC-20. The deploying account receives the entire supply once.
contract MirrorIMD is ERC20 {
    /// @notice One billion tokens expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev In a factory launch, msg.sender is the factory, which distributes the supply.
    constructor() ERC20("MirrorIMD", "MIRROR") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
