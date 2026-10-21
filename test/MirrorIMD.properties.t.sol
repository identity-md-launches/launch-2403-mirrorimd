// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MirrorIMD} from "../src/MirrorIMD.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase} from "./utils/TestBase.sol";

/// @dev Complements the basic ERC-20 tests with replay, boundary, and algebraic properties.
/// forge-config: default.fuzz.runs = 1024
contract MirrorIMDPropertiesTest is TestBase {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    MirrorIMD private token;

    function setUp() public {
        token = new MirrorIMD();
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        assertTrue(token.approve(SPENDER, type(uint256).max - 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unlimitedAllowanceCanBeReplacedWithFiniteAllowance() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertTrue(token.approve(SPENDER, 3));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 3));
        _expectNoAllowance(address(this), SPENDER, BOB);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 4);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4);
    }

    function test_unlimitedAllowanceCanBeRevoked() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertTrue(token.approve(SPENDER, 0));
        _expectNoAllowance(address(this), SPENDER, ALICE);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_lastApprovedUnitCannotBeSpentTwice() public {
        assertTrue(token.transfer(ALICE, 2));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        // The owner still has funds: only exhaustion of the approval prevents the second spend.
        _expectNoAllowance(ALICE, SPENDER, BOB);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.allowance(ALICE, SPENDER), 0);
    }

    function test_refillingBalanceDoesNotRestoreSpentAllowance() public {
        assertTrue(token.transfer(ALICE, 2));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 2));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 2));
        assertTrue(token.transfer(ALICE, 3));
        _expectNoAllowance(ALICE, SPENDER, BOB);
        assertEq(token.balanceOf(ALICE), 3);
        assertEq(token.balanceOf(BOB), 2);
        assertEq(token.allowance(ALICE, SPENDER), 0);

        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 3));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 3));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 5);
        assertEq(token.balanceOf(address(this)), SUPPLY - 5);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unlimitedAllowanceDoesNotBypassBalanceChecks() public {
        assertTrue(token.transfer(ALICE, 1));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1, 2));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 2);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferCannotBypassBalanceChecks() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ownerSpenderAndRecipientCanBeTheSameAccount() public {
        assertTrue(token.approve(address(this), SUPPLY));
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), address(this)), 0);
        _expectNoAllowance(address(this), address(this), address(this));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroDelegatedTransferToZeroRevertsForFiniteAndUnlimitedApproval() public {
        assertTrue(token.approve(SPENDER, 1));
        _expectInvalidRecipient(0);
        assertEq(token.allowance(address(this), SPENDER), 1);

        assertTrue(token.approve(SPENDER, type(uint256).max));
        _expectInvalidRecipient(0);
        _expectInvalidRecipient(1);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvalBeforeFundingIsUsableAfterFunding() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, type(uint256).max - 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertTrue(token.transfer(ALICE, SUPPLY));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, SUPPLY));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max - 1 - SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferToArbitraryNonzeroRecipient(address recipient, uint256 amount) public {
        recipient = address(uint160(bound(uint160(recipient), 1, type(uint160).max)));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        if (recipient == address(this)) {
            assertEq(token.balanceOf(recipient), SUPPLY);
        } else {
            assertEq(token.balanceOf(recipient), amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        }
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferRoundTripRestoresBalances(uint256 balance, uint256 amount) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, 0, balance);
        assertTrue(token.transfer(ALICE, balance));
        // A pre-existing recipient balance catches round trips that incorrectly empty the recipient.
        assertTrue(token.transfer(BOB, SUPPLY - balance));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.balanceOf(BOB), SUPPLY - balance + amount);
        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), SUPPLY - balance);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitTransferEqualsLumpSum(uint256 amount, uint256 first) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        MirrorIMD lumpSumToken = new MirrorIMD();
        assertTrue(token.transfer(ALICE, first));
        assertTrue(token.transfer(ALICE, amount - first));
        assertTrue(lumpSumToken.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(ALICE), lumpSumToken.balanceOf(ALICE));
        assertEq(token.balanceOf(address(this)), lumpSumToken.balanceOf(address(this)));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(lumpSumToken.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalOverwriteIsIdempotent(uint256 original, uint256 replacement) public {
        assertTrue(token.approve(SPENDER, original));
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(address(this), SPENDER), replacement);
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(address(this), SPENDER), replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedDelegatedSpendIsAtomic(uint256 balance, uint256 amount, bool unlimited) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max);
        uint256 approved = unlimited ? type(uint256).max : amount;
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.allowance(ALICE, SPENDER), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_finiteAllowanceCanBeExhaustedButNotReplayed(uint256 allowed, uint256 first) public {
        // Leave at least one unit in the owner after spending, isolating the allowance failure.
        allowed = bound(allowed, 1, SUPPLY - 1);
        first = bound(first, 0, allowed);
        assertTrue(token.approve(SPENDER, allowed));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, first));
        assertEq(token.allowance(address(this), SPENDER), allowed - first);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, allowed - first));
        _expectNoAllowance(address(this), SPENDER, ALICE);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), first);
        assertEq(token.balanceOf(BOB), allowed - first);
        assertEq(token.balanceOf(address(this)), SUPPLY - allowed);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_revocationDoesNotAffectOtherSpendersOrOwners(uint256 first, uint256 second) public {
        assertTrue(token.approve(SPENDER, first));
        assertTrue(token.approve(BOB, second));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, second));
        assertTrue(token.approve(SPENDER, 0));
        _expectNoAllowance(address(this), SPENDER, BOB);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.allowance(address(this), BOB), second);
        assertEq(token.allowance(ALICE, SPENDER), second);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _expectNoAllowance(address owner, address spender, address to) private {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
    }

    function _expectInvalidRecipient(uint256 amount) private {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), amount);
    }
}
