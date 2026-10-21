// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ForeverToken} from "../src/ForeverToken.sol";

/// @dev Complements the basic ERC-20 suite with arithmetic boundaries and operation sequences.
/// forge-config: default.fuzz.runs = 1024
contract ForeverTokenPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    ForeverToken private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new ForeverToken();
        alice = makeAddr("property alice");
        bob = makeAddr("property bob");
        spender = makeAddr("property spender");
    }

    function test_oneBaseUnitArrivesWithoutRounding() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 1);
        assertTrue(token.transfer(alice, 1));
        _assertBalances(SUPPLY - 1, 1, 0);

        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_maximumTransferRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_maximumFiniteAllowanceIsConsumed() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function test_infiniteApprovalCanBeReducedAndRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1, 2));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 2);
        assertEq(token.allowance(address(this), spender), 1);
        _assertBalances(SUPPLY - 1, 1, 0);

        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function test_infiniteApprovalDoesNotPermitSpendingBeyondSupply() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_zeroApprovalStillRejectsZeroSpender() public {
        assertTrue(token.approve(spender, 7));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 7);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_zeroDelegatedTransferStillRejectsZeroReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_approvalDoesNotFollowTransferredTokens() public {
        assertTrue(token.approve(spender, SUPPLY));
        assertTrue(token.transfer(alice, SUPPLY));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(0, SUPPLY, 0);
    }

    function testFuzz_approvalReplacementIsIdempotentAndIsolated(uint256 first, uint256 replacement) public {
        assertTrue(token.approve(spender, 23));
        vm.startPrank(alice);
        assertTrue(token.approve(bob, 17));
        assertTrue(token.approve(spender, first));
        assertEq(token.allowance(alice, spender), first);

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(alice, spender, replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(alice, spender), replacement);
        assertTrue(token.approve(spender, replacement));
        vm.stopPrank();

        assertEq(token.allowance(alice, spender), replacement);
        assertEq(token.allowance(alice, bob), 17);
        assertEq(token.allowance(address(this), spender), 23);
        assertEq(token.allowance(spender, alice), 0);
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_transferRoundTripRestoresBalancesAndPreservesApproval(
        uint256 aliceBalance,
        uint256 bobBalance,
        uint256 amount,
        uint256 approved
    ) public {
        aliceBalance = bound(aliceBalance, 0, SUPPLY);
        bobBalance = bound(bobBalance, 0, SUPPLY - aliceBalance);
        amount = bound(amount, 0, aliceBalance);
        assertTrue(token.transfer(alice, aliceBalance));
        assertTrue(token.transfer(bob, bobBalance));
        vm.prank(alice);
        assertTrue(token.approve(bob, approved));

        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        _assertBalances(SUPPLY - aliceBalance - bobBalance, aliceBalance - amount, bobBalance + amount);
        assertEq(token.allowance(alice, bob), approved);

        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        _assertBalances(SUPPLY - aliceBalance - bobBalance, aliceBalance, bobBalance);
        assertEq(token.allowance(alice, bob), approved);
    }

    function testFuzz_splitDelegatedSpendMatchesSingleSpend(uint256 approved, uint256 amount, uint256 first) public {
        amount = bound(amount, 0, approved < SUPPLY ? approved : SUPPLY);
        first = bound(first, 0, amount);
        ForeverToken single = new ForeverToken();
        assertTrue(single.approve(spender, approved));
        assertTrue(token.approve(spender, approved));

        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertTrue(token.transferFrom(address(this), alice, amount - first));
        assertTrue(single.transferFrom(address(this), alice, amount));
        vm.stopPrank();

        _assertBalances(SUPPLY - amount, amount, 0);
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(single.totalSupply(), SUPPLY);
        uint256 remaining = approved == type(uint256).max ? approved : approved - amount;
        assertEq(token.allowance(address(this), spender), remaining);
        assertEq(token.allowance(address(this), spender), single.allowance(address(this), spender));
    }

    function testFuzz_failedDelegatedTransferCanBeRetriedAfterFunding(uint256 funded, uint256 requested, bool infinite)
        public
    {
        funded = bound(funded, 0, SUPPLY - 1);
        requested = bound(requested, funded + 1, SUPPLY);
        uint256 approved = infinite ? type(uint256).max : requested;
        assertTrue(token.transfer(alice, funded));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, funded, requested)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, requested);
        assertEq(token.allowance(alice, spender), approved);
        _assertBalances(SUPPLY - funded, funded, 0);

        // The same approval must remain usable when the owner receives the missing balance.
        assertTrue(token.transfer(alice, requested - funded));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, requested));
        assertEq(token.allowance(alice, spender), infinite ? type(uint256).max : 0);
        _assertBalances(SUPPLY - requested, 0, requested);
    }

    function _assertBalances(uint256 deployerBalance, uint256 aliceBalance, uint256 bobBalance) private view {
        assertEq(token.balanceOf(address(this)), deployerBalance);
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
