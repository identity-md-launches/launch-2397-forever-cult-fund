// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
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
}

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

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.move.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.moveApproved.selector;
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
    }

    function invariant_allowancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.modelAllowance(actors[i], actors[j]));
            }
        }
    }
}
