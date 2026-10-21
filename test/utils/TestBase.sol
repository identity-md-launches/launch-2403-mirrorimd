// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Only the Foundry cheatcodes used by this project's tests; no runtime dependency.
interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address sender) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "uint assertion failed");
    }

    function assertEq(address actual, address expected) internal pure {
        require(actual == expected, "address assertion failed");
    }

    function assertEq(bytes32 actual, bytes32 expected) internal pure {
        require(actual == expected, "bytes32 assertion failed");
    }

    function assertEq(string memory actual, string memory expected) internal pure {
        require(keccak256(bytes(actual)) == keccak256(bytes(expected)), "string assertion failed");
    }

    function assertTrue(bool condition) internal pure {
        require(condition, "bool assertion failed");
    }

    /// @dev Keep in-range inputs intact, including zero and the maximum. No discarded fuzz cases.
    function bound(uint256 value, uint256 minimum, uint256 maximum) internal pure returns (uint256) {
        require(minimum <= maximum, "invalid bounds");
        if (value >= minimum && value <= maximum) return value;
        // The full uint256 range always returned above, so the range size cannot overflow here.
        return minimum + value % (maximum - minimum + 1);
    }
}
