// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MirrorIMD} from "../src/MirrorIMD.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase} from "./utils/TestBase.sol";

/// @dev All balances stay in this closed set of actors. Ghost state changes only after successful
/// calls; rejected operations must leave it unchanged. No token storage is written by cheatcodes.
contract MirrorIMDHandler is TestBase {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    MirrorIMD public immutable token;
    address[4] private actors;
    uint256[4] public expectedBalance;
    mapping(uint256 owner => mapping(uint256 spender => uint256 amount)) public expectedAllowance;

    constructor() {
        token = new MirrorIMD();
        actors = [address(this), address(0xA11CE), address(0xB0B), address(0xCA401)];
        expectedBalance[0] = SUPPLY;
        // Start every actor funded so generated sequences exercise positive transfers immediately.
        for (uint256 i = 1; i < actors.length; ++i) {
            assertTrue(token.transfer(actors[i], SUPPLY / 4));
            expectedBalance[0] -= SUPPLY / 4;
            expectedBalance[i] = SUPPLY / 4;
        }
    }

    function actor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        uint256 from = fromSeed % 4;
        uint256 to = toSeed % 4;
        uint256 amount = _transferAmount(amountSeed, expectedBalance[from]);
        vm.prank(actors[from]);
        assertTrue(token.transfer(actors[to], amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool unlimited) external {
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        // Approvals may exceed the entire supply. Keep the full uint256 domain reachable.
        uint256 amount = unlimited ? type(uint256).max : amountSeed;
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
        uint256 amount = _transferAmount(amountSeed, limit);
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

    function revokeAndReject(uint256 ownerSeed, uint256 spenderSeed) external {
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        _approve(owner, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], 0, 1));
        vm.prank(actors[spender]);
        token.transferFrom(actors[owner], actors[(owner + 1) % 4], 1);
    }

    function rejectedAboveAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 allowanceSeed, uint256 amountSeed)
        external
    {
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 allowed = bound(allowanceSeed, 0, type(uint256).max - 1);
        uint256 amount = bound(amountSeed, allowed + 1, type(uint256).max);
        _approve(owner, spender, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], allowed, amount)
        );
        vm.prank(actors[spender]);
        token.transferFrom(actors[owner], actors[(owner + 1) % 4], amount);
    }

    function rejectedDelegatedOverdraft(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool unlimited)
        external
    {
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, actors[owner], balance, amount)
        );
        vm.prank(actors[spender]);
        token.transferFrom(actors[owner], actors[(owner + 1) % 4], amount);
        // In particular, the approval made above survives the failed spend in its entirety.
    }

    function rejectedZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated)
        external
    {
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 amount = _transferAmount(amountSeed, expectedBalance[owner]);
        if (delegated) _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? actors[spender] : actors[owner]);
        if (delegated) token.transferFrom(actors[owner], address(0), amount);
        else token.transfer(address(0), amount);
    }

    function rejectedZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(actors[ownerSeed % 4]);
        token.approve(address(0), amount);
    }

    function _approve(uint256 owner, uint256 spender, uint256 amount) private {
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        expectedAllowance[owner][spender] = amount;
    }

    /// @dev Deliberately exercise zero, one base unit, and the complete available balance/allowance
    /// as well as arbitrary amounts. Tiny and complete transfers must remain live after any history.
    function _transferAmount(uint256 seed, uint256 limit) private pure returns (uint256) {
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return limit;
        if (seed % 4 == 2) return limit == 0 ? 0 : 1;
        return bound(seed / 4, 0, limit);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
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
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = MirrorIMDHandler.transfer.selector;
        selectors[1] = MirrorIMDHandler.approve.selector;
        selectors[2] = MirrorIMDHandler.transferFrom.selector;
        selectors[3] = MirrorIMDHandler.rejectedOverdraft.selector;
        selectors[4] = MirrorIMDHandler.revokeAndReject.selector;
        selectors[5] = MirrorIMDHandler.rejectedAboveAllowance.selector;
        selectors[6] = MirrorIMDHandler.rejectedDelegatedOverdraft.selector;
        selectors[7] = MirrorIMDHandler.rejectedZeroRecipient.selector;
        selectors[8] = MirrorIMDHandler.rejectedZeroSpender.selector;
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
            assertEq(token.allowance(handler.actor(i), address(0)), 0);
            assertEq(token.allowance(address(0), handler.actor(i)), 0);
            for (uint256 j; j < 4; ++j) {
                assertEq(token.allowance(handler.actor(i), handler.actor(j)), handler.expectedAllowance(i, j));
            }
        }
    }
}
