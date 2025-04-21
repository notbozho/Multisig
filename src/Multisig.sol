// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Multisig
/// @author notbozho
/// @notice Simple multisig wallet with owner management and transaction approvals
/// @dev Owners can submit, approve, unapprove, and execute transactions
contract Multisig {
    // =================== Structs ===================

    struct Transaction {
        address to; // recipient
        uint256 value; // native funds transfered
        bytes data; // additional data
        uint256 approvals; // number of approvals
        bool executed; // is executed
        uint256 nonce;
    }

    struct PendingOwner {
        address invitedBy;
        uint48 expiresAt; // uint48 so it saves 1 storage slot => less gas
    }

    // =================== State Variables ===================

    uint48 public constant PENDING_OWNER_DURATION = 14 days;

    uint256 public nonce;

    mapping(bytes32 => Transaction) public transactions;
    // txHash => owner => isApproved
    mapping(bytes32 => mapping(address => bool)) public approvedBy;
    uint256 public minimumApprovals = 1;

    mapping(address => bool) public isOwner;
    mapping(address => PendingOwner) public pendingOwners;

    // =================== Events ===================

    event OwnerInvited(address indexed user, uint48 expiresAt, address indexed invitedBy);
    event NewOwner(address indexed user, address indexed invitedBy);
    event OwnerRenounced(address indexed user);

    event TransactionSubmitted(
        address indexed owner,
        bytes32 indexed txHash,
        address indexed recipient,
        uint256 value,
        bytes data
    );
    event TransactionExecuted(
        address indexed recipient,
        uint256 value,
        bytes data,
        uint256 approvals,
        bytes32 indexed txHash,
        address indexed owner
    );
    event TransactionApproved(bytes32 indexed txHash, address indexed owner);
    event TransactionUnapproved(
        bytes32 indexed txHash, address indexed owner, bool isTxDeleted
    );

    // =================== Errors ===================

    error InvalidParameter(string param);

    error NotOwner();
    error OwnerNotInvited(address user);
    error OwnerInviteExpired(address user, uint48 expiredAt);
    error UserAlreadyOwner(address user);

    error TxNotFound(bytes32 txHash);
    error TxAlreadyExecuted(bytes32 txHash);
    error TxAlreadySubmitted(bytes32 txHash);
    error TxAlreadyApproved(bytes32 txHash, address owner);
    error TxNotApproved(bytes32 txHash, address owner);
    error TxNotEnoughApprovals(
        bytes32 txHash, uint256 currentApprovals, uint256 requiredApprovals
    );
    error TxFailed(bytes32 txHash, bytes result);

    // =================== Modifiers ===================

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) {
            revert NotOwner();
        }
        _;
    }

    // more gas costly in exchange for better readability
    modifier txExists(bytes32 txHash) {
        if (transactions[txHash].approvals == 0) {
            revert TxNotFound(txHash);
        }
        _;
    }

    modifier txNotExecuted(bytes32 txHash) {
        if (transactions[txHash].executed) {
            revert TxAlreadyExecuted(txHash);
        }
        _;
    }

    // =================== Functions ===================

    constructor() {
        isOwner[msg.sender] = true;
    }

    /**
     * OWNER MANAGEMENT
     */
    function addOwner(address user) external onlyOwner {
        if (user == address(0)) {
            revert InvalidParameter("user");
        }

        if (isOwner[user]) {
            revert UserAlreadyOwner(user);
        }

        uint48 expiresAt = uint48(block.timestamp) + PENDING_OWNER_DURATION;
        pendingOwners[user] =
            PendingOwner({ invitedBy: msg.sender, expiresAt: expiresAt });

        emit OwnerInvited(user, expiresAt, msg.sender);
    }

    function acceptOwnership() external {
        PendingOwner memory _pending = pendingOwners[msg.sender];

        if (_pending.expiresAt == 0) {
            revert OwnerNotInvited(msg.sender);
        }

        if (_pending.expiresAt < block.timestamp) {
            revert OwnerInviteExpired(msg.sender, _pending.expiresAt);
        }

        isOwner[msg.sender] = true;
        minimumApprovals++;
        delete pendingOwners[msg.sender];

        emit NewOwner(msg.sender, _pending.invitedBy);
    }

    function renounceOwnership() external onlyOwner {
        require(minimumApprovals > 1, "min 1 owner is required");

        delete isOwner[msg.sender];
        minimumApprovals--;

        emit OwnerRenounced(msg.sender);
    }

    /**
     * TRANSACTIONS
     */
    function submitTransaction(address recipient, uint256 value, bytes calldata data)
        external
        onlyOwner
    {
        bytes32 txHash = getTxHash(recipient, value, data, nonce);
        // cache to save gas
        Transaction memory _tx = transactions[txHash];

        if (_tx.executed) {
            // this shouldn't happen
            revert TxAlreadyExecuted(txHash);
        }
        if (_tx.approvals > 0) {
            revert TxAlreadySubmitted(txHash);
        }

        transactions[txHash] = Transaction({
            to: recipient,
            value: value,
            data: data,
            approvals: 1,
            executed: false,
            nonce: nonce
        });

        approvedBy[txHash][msg.sender] = true;

        nonce++;

        emit TransactionSubmitted(msg.sender, txHash, recipient, value, data);
    }

    function approveTransaction(bytes32 txHash)
        external
        onlyOwner
        txExists(txHash)
        txNotExecuted(txHash)
    {
        if (approvedBy[txHash][msg.sender]) {
            revert TxAlreadyApproved(txHash, msg.sender);
        }

        Transaction memory _tx = transactions[txHash];

        if (_tx.executed) {
            revert TxAlreadyExecuted(txHash);
        }

        approvedBy[txHash][msg.sender] = true;
        transactions[txHash].approvals++;

        emit TransactionApproved(txHash, msg.sender);
    }

    function unapproveTransaction(bytes32 txHash)
        external
        onlyOwner
        txExists(txHash)
        txNotExecuted(txHash)
    {
        if (!approvedBy[txHash][msg.sender]) {
            revert TxNotApproved(txHash, msg.sender);
        }

        delete approvedBy[txHash][msg.sender];
        transactions[txHash].approvals--;

        if (transactions[txHash].approvals == 0) {
            delete transactions[txHash];
        }

        emit TransactionUnapproved(
            txHash, msg.sender, transactions[txHash].approvals == 0
        );
    }

    function executeTransaction(bytes32 txHash)
        external
        onlyOwner
        txExists(txHash)
        txNotExecuted(txHash)
    {
        Transaction memory _tx = transactions[txHash];

        // uint256 ownersLen = owners.length; // cache to reduce storage reads
        if (_tx.approvals < minimumApprovals) {
            revert TxNotEnoughApprovals(txHash, _tx.approvals, minimumApprovals);
        }

        transactions[txHash].executed = true;

        // CEI pattern
        (bool success, bytes memory result) = _tx.to.call{ value: _tx.value }(_tx.data);
        if (!success) revert TxFailed(txHash, result);

        emit TransactionExecuted(
            _tx.to, _tx.value, _tx.data, _tx.approvals, txHash, msg.sender
        );
    }

    function getTxHash(
        address recipient,
        uint256 value,
        bytes calldata data,
        uint256 _nonce
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(recipient, value, data, _nonce));
    }

    function getTransaction(bytes32 txHash)
        public
        view
        returns (
            address recipient,
            uint256 value,
            bytes memory data,
            uint256 approvals,
            bool executed
        )
    {
        Transaction memory _tx = transactions[txHash];

        return (_tx.to, _tx.value, _tx.data, _tx.approvals, _tx.executed);
    }

    function balance() public view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable { }

    fallback() external payable { }
}
