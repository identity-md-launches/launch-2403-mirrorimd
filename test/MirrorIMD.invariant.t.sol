// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MirrorIMD} from "../src/MirrorIMD.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase} from "./utils/TestBase.sol";

/// @dev Generates sequences of direct and delegated transfers, approvals, and rejected overdrafts.
contract MirrorIMDHandler is TestBase {
    MirrorIMD public immutable token;
    address[4] private actors;
    uint256[4] public expectedBalance;
    mapping(uint256 owner => mapping(uint256 spender => uint256 amount)) public expectedAllowance;

    constructor() {
        token = new MirrorIMD();
        actors = [address(this), address(0xA11CE), address(0xB0B), address(0xCA401)];
        expectedBalance[0] = 1_000_000_000 * 10 ** 18;
    }

    function actor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        uint256 from = fromSeed % 4;
        uint256 to = toSeed % 4;
        uint256 amount = amountSeed % (expectedBalance[from] + 1);
        vm.prank(actors[from]);
        assertTrue(token.transfer(actors[to], amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool unlimited) external {
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 amount = unlimited ? type(uint256).max : amountSeed % (token.INITIAL_SUPPLY() + 1);
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed) external {
        uint256 from = fromSeed % 4;
        uint256 to = toSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 allowed = expectedAllowance[from][spender];
        uint256 limit = expectedBalance[from] < allowed ? expectedBalance[from] : allowed;
        uint256 amount = amountSeed % (limit + 1);
        vm.prank(actors[spender]);
        assertTrue(token.transferFrom(actors[from], actors[to], amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) expectedAllowance[from][spender] -= amount;
    }

    function rejectedOverdraft(uint256 fromSeed, uint256 toSeed) external {
        uint256 from = fromSeed % 4;
        uint256 to = toSeed % 4;
        uint256 amount = expectedBalance[from] + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, actors[from], expectedBalance[from], amount
            )
        );
        vm.prank(actors[from]);
        token.transfer(actors[to], amount);
    }
}

contract MirrorIMDInvariantTest is TestBase {
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    MirrorIMDHandler private handler;
    MirrorIMD private token;

    function setUp() public {
        handler = new MirrorIMDHandler();
        token = handler.token();
    }

    /// @dev Foundry's invariant runner discovers these targets without forge-std.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        targets = new FuzzSelector[](1);
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = MirrorIMDHandler.transfer.selector;
        selectors[1] = MirrorIMDHandler.approve.selector;
        selectors[2] = MirrorIMDHandler.transferFrom.selector;
        selectors[3] = MirrorIMDHandler.rejectedOverdraft.selector;
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    function invariant_supplyAndBalancesAreConserved() public view {
        uint256 total;
        for (uint256 i; i < 4; ++i) {
            uint256 balance = token.balanceOf(handler.actor(i));
            assertEq(balance, handler.expectedBalance(i));
            total += balance;
        }
        assertEq(total, 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), total);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_allowancesMatchApprovalsAndSpending() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                assertEq(token.allowance(handler.actor(i), handler.actor(j)), handler.expectedAllowance(i, j));
            }
        }
    }
}
