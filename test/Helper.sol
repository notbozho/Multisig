// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { Multisig } from "src/Multisig.sol";

contract Helper is Test {

    Multisig public multisig;
    address public initialOwner;

    function setUp() public virtual {
        vm.prank(initialOwner);
        multisig = new Multisig();
        // give some eth to the wallet for transactions
        vm.deal(address(multisig), 100 ether);
    }

    function addOwner(address user) internal {
        vm.prank(initialOwner);
        multisig.addOwner(user);

        vm.prank(user);
        multisig.acceptOwnership();
    }

    function submitTransaction(address recipient, uint256 value, bytes memory data)
        internal
        returns (bytes32)
    {
        return multisig.submitTransaction(recipient, value, data);
    }

    function approveTransaction(bytes32 txHash) internal {
        multisig.approveTransaction(txHash);
    }

    function unapproveTransaction(bytes32 txHash) internal {
        multisig.unapproveTransaction(txHash);
    }

    function executeTransaction(bytes32 txHash) internal {
        multisig.executeTransaction(txHash);
    }

    function getTxRecipient(bytes32 txHash) internal view returns (address) {
        (address recipient,,,,) = multisig.getTransaction(txHash);

        return recipient;
    }

    function getTxApprovals(bytes32 txHash) internal view returns (uint256) {
        (,,, uint256 approvals,) = multisig.getTransaction(txHash);

        return approvals;
    }

    function isTxExecuted(bytes32 txHash) internal view returns (bool) {
        (,,,, bool executed) = multisig.getTransaction(txHash);

        return executed;
    }

}