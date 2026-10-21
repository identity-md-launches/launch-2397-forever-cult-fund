// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ForeverToken} from "../src/ForeverToken.sol";

/// @dev Stateful model of transfers and approvals among a closed set of token holders.
contract ForeverTokenHandler is Test {
    ForeverToken private immutable token;
    address[4] private actors;
    mapping(address account => uint256) public modelBalance;
    mapping(address owner => mapping(address spender => uint256)) public modelAllowance;

    constructor(ForeverToken token_, address[4] memory actors_, uint256 supply) {
        token = token_;
        actors = actors_;
        modelBalance[actors_[0]] = supply;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, modelBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        modelBalance[from] -= amount;
        modelBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        modelAllowance[owner][spender] = amount;
    }

    function moveApproved(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = modelAllowance[owner][spender];
        uint256 available = modelBalance[owner];
        amount = bound(amount, 0, approved < available ? approved : available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        modelBalance[owner] -= amount;
        modelBalance[to] += amount;
        if (approved != type(uint256).max) {
            modelAllowance[owner][spender] -= amount;
        }
    }

    function moveAll(uint256 fromSeed, uint256 toSeed) public {
        move(fromSeed, toSeed, modelBalance[actors[fromSeed % actors.length]]);
    }

    /// @dev Make revocation and the finite/infinite allowance boundary frequent sequence steps.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 boundarySeed) public {
        uint256[4] memory amounts = [uint256(0), uint256(1), type(uint256).max - 1, type(uint256).max];
        approve(ownerSeed, spenderSeed, amounts[boundarySeed % amounts.length]);
    }

    // Failed calls leave the ghost model untouched. The invariants compare every balance and
    // allowance afterwards, including unrelated accounts, so partial mutations cannot hide.
    function rejectOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 available = modelBalance[from];
        amount = bound(amount, available + 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, available, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function rejectOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 approved) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        approved = bound(approved, 0, type(uint256).max - 1);
        approve(ownerSeed, spenderSeed, approved);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, approved + 1);
    }

    function rejectApprovedOverBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amount,
        bool infinite
    ) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 available = modelBalance[owner];
        amount = bound(amount, available + 1, type(uint256).max - 1);
        approve(ownerSeed, spenderSeed, infinite ? type(uint256).max : amount);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, available, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, modelBalance[owner]);
        if (delegated) {
            // Keep a finite, nonzero allowance so a failed transfer must roll back its consumption.
            approve(ownerSeed, spenderSeed, amount + 1);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract ForeverTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    ForeverToken private token;
    ForeverTokenHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new ForeverToken();
        actors = [makeAddr("holder one"), makeAddr("holder two"), makeAddr("holder three"), makeAddr("holder four")];
        handler = new ForeverTokenHandler(token, actors, SUPPLY);
        assertTrue(token.transfer(actors[0], SUPPLY));

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.move.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.moveApproved.selector;
        selectors[3] = handler.moveAll.selector;
        selectors[4] = handler.approveBoundary.selector;
        selectors[5] = handler.rejectOverBalance.selector;
        selectors[6] = handler.rejectOverAllowance.selector;
        selectors[7] = handler.rejectApprovedOverBalance.selector;
        selectors[8] = handler.rejectZeroReceiver.selector;
        selectors[9] = handler.rejectZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndBalancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.modelBalance(actors[i]));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_allowancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.modelAllowance(actors[i], actors[j]));
            }
        }
    }

    /// @dev Every holder must still be able to transfer their entire balance after a random sequence.
    function afterInvariant() public {
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.moveAll(i, 0);
            assertEq(token.balanceOf(actors[i]), 0);
        }
        assertEq(token.balanceOf(actors[0]), SUPPLY);
        invariant_supplyAndBalancesMatchModel();
        invariant_allowancesMatchModel();
        assertEq(token.name(), "Forever Cult Fund");
        assertEq(token.symbol(), "FOREVER");
        assertEq(token.decimals(), 18);
    }
}
