// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { Multisig } from "src/Multisig.sol";

// Every path twice
// Different order of calls
contract MultisigTest is Test { 

    Multisig public multisig;
    address public initialOwner;

    function setUp() public {
        vm.prank(initialOwner);
        multisig = new Multisig();
    }

    // deployer SHOULD be an owner 
    function test_initial_owner() public {
        assertTrue(multisig.isOwner(initialOwner));
    }

    // should ALLOW to invite a user as owner and him to accept it
    function test_twostep_ownership() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));
        assertFalse(multisig.isOwner(newOwner));

        vm.prank(initialOwner);
        vm.expectEmit(true, true, true, false);
        emit Multisig.OwnerInvited(newOwner, uint48(block.timestamp + 14 days), initialOwner);

        multisig.addOwner(newOwner);

        vm.prank(newOwner);
        vm.expectEmit(true, true, false ,false);
        emit Multisig.NewOwner(newOwner, initialOwner);
        multisig.acceptOwnership();

        assertTrue(multisig.isOwner(newOwner));
    }

    // should REVERT when owner invite is expired
    function test_twostep_ownership_expired() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));
        uint256 shouldExpireAt = block.timestamp + 14 days;

        assertFalse(multisig.isOwner(newOwner));

        vm.prank(initialOwner);
        vm.expectEmit(true, true, true, false);
        emit Multisig.OwnerInvited(newOwner, uint48(block.timestamp + 14 days), initialOwner);

        multisig.addOwner(newOwner);
        skip(14 days + 1);

        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(Multisig.OwnerInviteExpired.selector, newOwner, shouldExpireAt));
        multisig.acceptOwnership();

        assertFalse(multisig.isOwner(newOwner));
    }

    // should REVERT when uninvited user tries to gain ownership
    function test_twostep_ownership_uninvited() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));
        assertFalse(multisig.isOwner(newOwner));

        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(Multisig.OwnerNotInvited.selector, newOwner));
        multisig.acceptOwnership();
    
        assertFalse(multisig.isOwner(newOwner));
    }

    // should ALLOW a owner to renounce his ownership
    function test_renounce_ownership() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));

        addOwner(newOwner);

        assertTrue(multisig.isOwner(newOwner));

        vm.expectEmit();
        emit Multisig.OwnerRenounced(newOwner);
        vm.prank(newOwner);
        multisig.renounceOwnership();

        assertFalse(multisig.isOwner(newOwner));
    }
    
    // should REVERT when the only one left owner tries to renounce his ownership
    function test_renounce_ownership_one_owner() public {
        assertTrue(multisig.isOwner(initialOwner));
        assertEq(multisig.minimumApprovals(), 1);

        vm.prank(initialOwner);
        vm.expectRevert("min 1 owner is required");
        multisig.renounceOwnership();
    }

    // should REVERT if user without ownership tries to submit a transaction
    function test_submitTransaction_access_control() public {
        address randomUser = vm.addr(uint256(bytes32("randomUser")));
        assertFalse(multisig.isOwner(randomUser));

        vm.expectRevert(Multisig.NotOwner.selector);
        submitTransaction(address(0x123), 6, "");
    }

    // should ALLOW to submit a transaction
    function test_submitTransaction() public {
        vm.prank(initialOwner);

        submitTransaction(address(0x123), 123, "");

        // TODO: check if transaction exists in state variables
    }

    // should ALLOW to submit multiple transacitons with same targets, values, datas

    // should ALLOW to submit multiple transactions with different targets, values, datas

    function addOwner(address user) internal {
        vm.prank(initialOwner);
        multisig.addOwner(user);

        vm.prank(user);
        multisig.acceptOwnership();
    }

    function submitTransaction(address recipient, uint256 value, bytes memory data) internal {
        multisig.submitTransaction(recipient, value, data);

    }   
}
