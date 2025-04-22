// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Helper } from "test/Helper.sol";
import { Multisig } from "src/Multisig.sol";

contract MultisigTest is Helper {

    function setUp() public override {
        super.setUp();
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
        emit Multisig.OwnerInvited(
            newOwner, uint48(block.timestamp + 14 days), initialOwner
        );

        multisig.addOwner(newOwner);

        vm.prank(newOwner);
        vm.expectEmit(true, true, false, false);
        emit Multisig.NewOwner(newOwner, initialOwner);
        multisig.acceptOwnership();

        assertTrue(multisig.isOwner(newOwner));
    }

    // should INCREMENT minimumApprovals when adding new owner
    function test_minimumApprovals_increment() public {
        uint256 minimumApprovals_before = multisig.minimumApprovals();
        assertEq(minimumApprovals_before, 1);
        address newOwner = vm.addr(uint256(bytes32("newOwner")));

        addOwner(newOwner);

        uint256 minimumApprovals_after = multisig.minimumApprovals();
        assertEq(minimumApprovals_before + 1, minimumApprovals_after);
    }

    // should REVERT when owner invite is expired
    function test_twostep_ownership_expired() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));
        uint256 shouldExpireAt = block.timestamp + 14 days;

        assertFalse(multisig.isOwner(newOwner));

        vm.prank(initialOwner);
        vm.expectEmit(true, true, true, false);
        emit Multisig.OwnerInvited(
            newOwner, uint48(block.timestamp + 14 days), initialOwner
        );

        multisig.addOwner(newOwner);
        skip(14 days + 1);

        vm.prank(newOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.OwnerInviteExpired.selector, newOwner, shouldExpireAt
            )
        );
        multisig.acceptOwnership();

        assertFalse(multisig.isOwner(newOwner));
    }

    // should REVERT if trying to invite existing owner
    function test_twostep_ownership_already_owner() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));
        addOwner(newOwner);

        assertTrue(multisig.isOwner(newOwner));
        
        vm.prank(initialOwner);
        vm.expectRevert(abi.encodeWithSelector(Multisig.UserAlreadyOwner.selector, newOwner));
        multisig.addOwner(newOwner);
    }

    // should REVERT if trying to invite zero address
    function test_twostep_ownership_zero_address() public {
        vm.prank(initialOwner);
        vm.expectRevert(abi.encodeWithSelector(Multisig.InvalidParameter.selector, "user"));
        multisig.addOwner(address(0));
    }

    // should REVERT when uninvited user tries to gain ownership
    function test_twostep_ownership_uninvited() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));
        assertFalse(multisig.isOwner(newOwner));

        vm.prank(newOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Multisig.OwnerNotInvited.selector, newOwner)
        );
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
        vm.startPrank(initialOwner);
        uint256 currentNonce = multisig.nonce();
        bytes32 txHash = multisig.getTxHash(address(0x123), 123, "", currentNonce);

        bytes32 returnedTxHash = submitTransaction(address(0x123), 123, "");
        assertEq(txHash, returnedTxHash);
        (address to, uint256 value, bytes memory data, uint256 approvals,) =
            multisig.getTransaction(txHash);
        assertEq(to, address(0x123));
        assertEq(value, 123);
        assertEq(data, "");
        assertEq(approvals, 1);
    }

    // should ALLOW to submit multiple transacitons with same targets, values, datas
    function test_submitTransaction_same_params_multiple_times() public {
        vm.startPrank(initialOwner);

        for (uint256 i; i <= 3; i++) {
            uint256 currentNonce = multisig.nonce();
            bytes32 txHash = multisig.getTxHash(address(0x123), 123, "", currentNonce);
            bytes32 returnedTxHash = submitTransaction(address(0x123), 123, "");
            assertEq(txHash, returnedTxHash);
            (address to, uint256 value, bytes memory data, uint256 approvals,) =
                multisig.getTransaction(txHash);
            assertEq(to, address(0x123));
            assertEq(value, 123);
            assertEq(data, "");
            assertEq(approvals, 1);
        }
    }

    // should ALLOW to submit multiple transactions with different targets, values, datas
    function test_submitTransaction_diff_params_multiple_times() public {
        vm.startPrank(initialOwner);

        uint256 currentNonce = multisig.nonce();
        for (uint256 i; i <= 3; i++) {
            address recipient = address(uint160(99 + i));

            bytes32 txHash = multisig.getTxHash(recipient, i, "", currentNonce + i);
            bytes32 returnedTxHash = submitTransaction(recipient, i, "");
            assertEq(txHash, returnedTxHash);

            (address to, uint256 value, bytes memory data, uint256 approvals,) =
                multisig.getTransaction(txHash);

            assertEq(to, recipient);
            assertEq(value, i);
            assertEq(data, "");
            assertEq(approvals, 1);
        }
    }

    // should INCREMENT nonce after each transaction
    function test_submitTransaction_increment_nonce() public {
        vm.startPrank(initialOwner);

        uint256 currentNonce = multisig.nonce();
        assertEq(currentNonce, 0);

        for (uint256 i; i <= 3; i++) {
            bytes32 returnedTxHash = submitTransaction(address(0x123), i, "");
            assertEq(multisig.nonce(), currentNonce + i + 1);
        }
    }

    // should REVERT submit transaction if recipient is multisig's own address
    function test_submitTransaction_own_address() public {
        vm.prank(initialOwner);

        vm.expectRevert(abi.encodeWithSelector(Multisig.InvalidParameter.selector, "recipient"));
        submitTransaction(address(multisig), 123, "");
    }

    // should ALLOW to approve existing transactions as owner
    function test_approveTransaciton() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));
        addOwner(newOwner);

        vm.prank(initialOwner);
        bytes32 txHash = submitTransaction(address(0x123), 123, "");

        uint256 txApprovals_before = getTxApprovals(txHash);

        vm.prank(newOwner);
        approveTransaction(txHash);

        uint256 txApprovals_after = getTxApprovals(txHash);
        assertEq(txApprovals_before + 1, txApprovals_after);
    }

    // should REVERT when trying to approve executed transaction
    function test_approveTransaction_executed() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));

        vm.startPrank(initialOwner);
        bytes32 txHash = submitTransaction(address(0x123), 123, "");
        executeTransaction(txHash);
        vm.stopPrank();

        addOwner(newOwner);

        vm.prank(newOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Multisig.TxAlreadyExecuted.selector, txHash)
        );
        approveTransaction(txHash);
    }

    // should REVERT when trying to approve twice
    function test_approveTransaciton_twice() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));

        vm.prank(initialOwner);
        bytes32 txHash = submitTransaction(address(0x123), 123, "");

        addOwner(newOwner);

        vm.startPrank(newOwner);
        approveTransaction(txHash);
        vm.expectRevert(
            abi.encodeWithSelector(Multisig.TxAlreadyApproved.selector, txHash, newOwner)
        );
        approveTransaction(txHash);
    }

    // should REVERT when trying to approve a non existent transaction
    function test_approveTransaciton_non_existent() public {
        bytes32 invalid_txHash = multisig.getTxHash(address(0x123), 123, "", 999);

        vm.prank(initialOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Multisig.TxNotFound.selector, invalid_txHash)
        );
        approveTransaction(invalid_txHash);
    }

    // should REVERT when trying to approve existing transaction without ownership
    function test_approveTransaciton_access_control() public {
        address randomUser = vm.addr(uint256(bytes32("randomUser")));

        vm.prank(initialOwner);
        bytes32 txHash = submitTransaction(address(0x123), 123, "");

        vm.prank(randomUser);
        vm.expectRevert(Multisig.NotOwner.selector);
        approveTransaction(txHash);
    }
    // should ALLOW to unapprove existing and approved transactions

    function test_unapproveTransaction() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));

        vm.prank(initialOwner);
        bytes32 txHash = submitTransaction(address(0x123), 123, "");

        addOwner(newOwner);

        vm.startPrank(newOwner);
        approveTransaction(txHash);

        uint256 txApprovals_before = getTxApprovals(txHash);
        assertTrue(multisig.approvedBy(txHash, newOwner));

        unapproveTransaction(txHash);
        uint256 txApprovals_after = getTxApprovals(txHash);

        assertEq(txApprovals_before - 1, txApprovals_after);
        assertFalse(multisig.approvedBy(txHash, newOwner));
    }

    // should REVERT when trying to unapprove transaction that wasn't approved in the first place
    function test_unapproveTransaction_unapproved() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));

        vm.prank(initialOwner);
        bytes32 txHash = submitTransaction(address(0x123), 123, "");

        addOwner(newOwner);

        assertFalse(multisig.approvedBy(txHash, newOwner));

        vm.startPrank(newOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Multisig.TxNotApproved.selector, txHash, newOwner)
        );
        unapproveTransaction(txHash);
    }

    // should DELETE transaction from storage if all owners unapprove
    function test_unapproveTransaction_delete_storage() public {
        vm.startPrank(initialOwner);
        bytes32 txHash = submitTransaction(address(0x123), 123, "");

        assertEq(getTxApprovals(txHash), 1);
        assertEq(getTxRecipient(txHash), address(0x123));
        assertNotEq(getTxRecipient(txHash), address(0x0));

        unapproveTransaction(txHash);

        assertEq(getTxApprovals(txHash), 0);
        assertNotEq(getTxRecipient(txHash), address(0x123));
        assertEq(getTxRecipient(txHash), address(0x0));
    }

    // should ALLOW executing transactions when all owners approve
    function test_executeTransaction() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));
        addOwner(newOwner);

        vm.prank(initialOwner);
        bytes32 txHash = submitTransaction(address(0x123), 123, "");

        vm.prank(newOwner);
        approveTransaction(txHash);

        uint256 txApprovals = getTxApprovals(txHash);
        assertEq(txApprovals, multisig.minimumApprovals());

        vm.prank(newOwner);
        vm.expectCall(address(0x123), 123, "");
        executeTransaction(txHash);
        assertTrue(isTxExecuted(txHash));
    }

    // should REVERT when trying to execute transaction that's not approved by all owners
    function test_executeTransaction_not_approved() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));
        addOwner(newOwner);

        vm.prank(initialOwner);
        bytes32 txHash = submitTransaction(address(0x123), 123, "");

        uint256 txApprovals = getTxApprovals(txHash);
        assertEq(txApprovals, multisig.minimumApprovals() - 1);

        vm.startPrank(newOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.TxNotEnoughApprovals.selector,
                txHash,
                getTxApprovals(txHash),
                multisig.minimumApprovals()
            )
        );
        executeTransaction(txHash);
    }

    // should REVERT if execute transaction returns success false
    function test_executeTransaction_not_successful() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));
        addOwner(newOwner);

        vm.startPrank(initialOwner);
        // large amount so it fails
        bytes32 txHash = submitTransaction(address(0x123), multisig.balance() + 1, "");
        vm.stopPrank();
         
        vm.prank(newOwner);
        approveTransaction(txHash);

        uint256 txApprovals = getTxApprovals(txHash);
        assertEq(txApprovals, multisig.minimumApprovals());

        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(Multisig.TxFailed.selector, txHash, ""));
        executeTransaction(txHash);

        assertFalse(isTxExecuted(txHash));
    }

    // should ALLOW to execute transaction that failed before
    function test_executeTransaction_success_with_past_revert() public {
        address newOwner = vm.addr(uint256(bytes32("newOwner")));
        addOwner(newOwner);

        vm.startPrank(initialOwner);
        // very large amount so it fails
        bytes32 txHash = submitTransaction(address(0x123), multisig.balance() + 1, "");
        vm.stopPrank();
        vm.prank(newOwner);
        approveTransaction(txHash);

        uint256 txApprovals = getTxApprovals(txHash);
        assertEq(txApprovals, multisig.minimumApprovals());

        vm.startPrank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(Multisig.TxFailed.selector, txHash, ""));
        executeTransaction(txHash);

        assertFalse(isTxExecuted(txHash));

        vm.deal(address(multisig), 1000000 ether);

        vm.startPrank(newOwner);
        executeTransaction(txHash);
        assertTrue(isTxExecuted(txHash));
    }

    // should RETURN multisigs balance
    function test_balance() public {
        assertEq(multisig.balance(), address(multisig).balance);
    }


}
