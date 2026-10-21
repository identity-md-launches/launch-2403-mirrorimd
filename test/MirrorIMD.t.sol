// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MirrorIMD} from "../src/MirrorIMD.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase, Vm} from "./utils/TestBase.sol";

/// @dev Test-only factory: verifies the constructor credits the immediate deployer.
contract TokenFactoryFixture {
    function deploy() external returns (MirrorIMD) {
        return new MirrorIMD();
    }

    function move(MirrorIMD token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract MirrorIMDTest is TestBase {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    MirrorIMD private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new MirrorIMD();
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "MirrorIMD");
        assertEq(token.symbol(), "MIRROR");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        MirrorIMD fresh = new MirrorIMD();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_factoryReceivesWholeSupply() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        MirrorIMD launched = factory.deploy();
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.balanceOf(address(launched)), 0);
    }

    function test_factoryDistributionAndClaimTransfersArriveWhole() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        MirrorIMD launched = factory.deploy();
        address distributor = address(0xD157);
        address pool = address(0x9001);
        uint256 swarm = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 8 / 10;
        uint256 remainder = SUPPLY - swarm - poolShare;

        assertTrue(factory.move(launched, distributor, swarm));
        assertTrue(factory.move(launched, pool, poolShare));
        assertTrue(factory.move(launched, BOB, remainder));
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(pool), poolShare);
        assertEq(launched.balanceOf(BOB), remainder);
        vm.prank(distributor);
        assertTrue(launched.transfer(ALICE, swarm));
        assertEq(launched.balanceOf(ALICE), swarm);
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_transferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 125 ether);
        assertTrue(token.transfer(ALICE, 125 ether));
        assertEq(token.balanceOf(ALICE), 125 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 125 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireSupply() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_transferSingleBaseUnit() public {
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToZeroRevertsWithoutChangingState() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferToZeroAlsoReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_transferFromZeroSenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 0);
    }

    function test_insufficientBalanceRevertsWithoutChangingState() public {
        token.transfer(ALICE, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 10 ether, 10 ether + 1)
        );
        vm.prank(ALICE);
        token.transfer(BOB, 10 ether + 1);
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferRevertsAsInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
    }

    function test_approveEmitsEventAndSetsAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 10 ether);
        assertTrue(token.approve(SPENDER, 10 ether));
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approvalCanBeReplacedAndRevoked() public {
        assertTrue(token.approve(SPENDER, 10 ether));
        assertTrue(token.approve(SPENDER, 3 ether));
        assertEq(token.allowance(address(this), SPENDER), 3 ether);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_approvalIsScopedToOwnerAndSpender() public {
        token.approve(SPENDER, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertEq(token.allowance(ALICE, SPENDER), 0);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_approveFromZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(SPENDER, 1);
    }

    function test_transferFromEmitsEventAndConsumesFiniteAllowance() public {
        token.approve(SPENDER, 10 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 4 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 4 ether));
        assertEq(token.allowance(address(this), SPENDER), 6 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);
        assertEq(token.balanceOf(ALICE), 4 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 6 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(BOB), 6 ether);
    }

    function test_infiniteAllowanceIsNotReduced() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 10 ether));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 10 ether);
    }

    function test_transferFromWithoutApprovalReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_transferFromAboveAllowanceReverts() public {
        token.approve(SPENDER, 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 1 ether, 2 ether)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 2 ether);
        assertEq(token.allowance(address(this), SPENDER), 1 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_failedTransferFromRollsBackAllowance() public {
        token.transfer(ALICE, 1 ether);
        vm.prank(ALICE);
        token.approve(SPENDER, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1 ether, 2 ether));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 2 ether);
        assertEq(token.allowance(ALICE, SPENDER), 10 ether);
        assertEq(token.balanceOf(ALICE), 1 ether);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromToZeroRollsBackAllowance() public {
        token.approve(SPENDER, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 1 ether);
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroAddressRevertsEvenForZeroAmount() public {
        // Spending even a zero allowance validates the approver before attempting the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_delegatedSelfTransferConsumesAllowanceWithoutChangingBalance() public {
        token.approve(SPENDER, 10 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_holderAlsoNeedsAllowanceForTransferFrom() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_noMintBurnOrAdminEntrypoints() public {
        token.transfer(ALICE, 100 ether);
        bytes[] memory calls = new bytes[](8);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, 1 ether);
        calls[1] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1 ether);
        calls[3] = abi.encodeWithSignature("pause()");
        calls[4] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[5] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[6] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[7] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        for (uint256 i; i < calls.length; ++i) {
            // The deployer has no authority either. Try each call as both deployer and stranger.
            (bool fromDeployer,) = address(token).call(calls[i]);
            assertTrue(!fromDeployer);
            vm.prank(BOB);
            (bool fromStranger,) = address(token).call(calls[i]);
            assertTrue(!fromStranger);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(ALICE), 100 ether);
        assertEq(token.balanceOf(BOB), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100 ether));
        assertEq(token.balanceOf(BOB), 100 ether);
    }

    function testFuzz_transferPreservesSupply(uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedTransferAccounting(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 allowed = rawAllowance % (SUPPLY + 1);
        uint256 amount = rawAmount % (allowed + 1);
        token.approve(SPENDER, allowed);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), SPENDER), allowed - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_aboveBalanceReverts(uint256 rawBalance, uint256 rawExcess) public {
        uint256 balance = rawBalance % (SUPPLY + 1);
        uint256 excess = 1 + rawExcess % SUPPLY;
        uint256 amount = balance + excess;
        token.transfer(ALICE, balance);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(ALICE);
        token.transfer(BOB, amount);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_aboveAllowanceReverts(uint256 rawAllowance, uint256 rawExcess) public {
        uint256 allowed = rawAllowance % SUPPLY;
        uint256 amount = allowed + 1 + rawExcess % (SUPPLY - allowed);
        token.approve(SPENDER, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, allowed, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        assertEq(token.allowance(address(this), SPENDER), allowed);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }
}
