// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Multisig
/// @author notbozho
/// @notice Simple multisig wallet with owner management and transaction approvals
/// @dev Owners can submit, approve, unapprove, and execute transactions
contract Multisig {
    // =================== Structs ===================

    /// @notice A transaction submitted for approval and execution
    struct Transaction {
        address to; // recipient
        uint256 value; // native funds transfered
        bytes data; // additional data
        uint256 approvals; // number of approvals
        bool executed; // is executed
        uint256 nonce;
    }

    /// @notice Temporary record of a user invited to become an owner
    struct PendingOwner {
        address invitedBy;
        uint48 expiresAt; // uint48 so it saves 1 storage slot => less gas
    }

    // =================== State Variables ===================

    /// @notice Duration for which an ownership invite remains valid
    uint48 public constant PENDING_OWNER_DURATION = 14 days;

    /// @notice Global transaction nonce
    uint256 public nonce;

    /// @notice Mapping of transaction hash to transaction details
    mapping(bytes32 txHash => Transaction transaction) public transactions;
    /// @notice Mapping of approvals for each transaction and owner
    mapping(bytes32 txHash => mapping(address owner => bool approved)) public approvedBy;
    /// @notice Minimum number of approvals required for transaction execution
    uint256 public minimumApprovals = 1;

    /// @notice Mapping to check if an address is an owner
    mapping(address => bool) public isOwner;
    /// @notice Mapping of pending owner invites
    mapping(address => PendingOwner) public pendingOwners;

    // =================== Events ===================

    /// @notice Emitted when an owner invites a new potential owner
    event OwnerInvited(address indexed user, uint48 expiresAt, address indexed invitedBy);

    /// @notice Emitted when a user accepts ownership
    event NewOwner(address indexed user, address indexed invitedBy);

    /// @notice Emitted when an owner renounces their ownership
    event OwnerRenounced(address indexed user);

    /// @notice Emitted when a transaction is submitted
    event TransactionSubmitted(
        address indexed owner,
        bytes32 indexed txHash,
        address indexed recipient,
        uint256 value,
        bytes data
    );

    /// @notice Emitted when a transaction is successfully executed
    event TransactionExecuted(
        address indexed recipient,
        uint256 value,
        bytes data,
        uint256 approvals,
        bytes32 indexed txHash,
        address indexed owner
    );
    /// @notice Emitted when a transaction is approved
    event TransactionApproved(bytes32 indexed txHash, address indexed owner);

    /// @notice Emitted when a transaction is unapproved
    event TransactionUnapproved(
        bytes32 indexed txHash, address indexed owner, bool isTxDeleted
    );

    // =================== Errors ===================

    /// @notice Raised when an invalid parameter is passed
    error InvalidParameter(string param);

    /// @notice Raised when caller is not an owner
    error NotOwner();

    /// @notice Raised when an uninvited user tries to accept ownership
    error OwnerNotInvited(address user);

    /// @notice Raised when an invite has expired
    error OwnerInviteExpired(address user, uint48 expiredAt);

    /// @notice Raised when a user is already an owner
    error UserAlreadyOwner(address user);

    /// @notice Raised when a transaction doesn't exist
    error TxNotFound(bytes32 txHash);

    /// @notice Raised when a transaction has already been executed
    error TxAlreadyExecuted(bytes32 txHash);

    /// @notice Raised when a transaction has already been submitted
    error TxAlreadySubmitted(bytes32 txHash);

    /// @notice Raised when an owner has already approved the transaction
    error TxAlreadyApproved(bytes32 txHash, address owner);

    /// @notice Raised when an owner tries to unapprove without prior approval
    error TxNotApproved(bytes32 txHash, address owner);

    /// @notice Raised when a transaction has insufficient approvals to execute
    error TxNotEnoughApprovals(
        bytes32 txHash, uint256 currentApprovals, uint256 requiredApprovals
    );

    /// @notice Raised when a transaction execution fails
    error TxFailed(bytes32 txHash, bytes result);

    // =================== Modifiers ===================

    /// @notice Restricts function to only owners
    modifier onlyOwner() {
        if (!isOwner[msg.sender]) {
            revert NotOwner();
        }
        _;
    }

    /// @notice Ensures that a transaction exists
    modifier txExists(bytes32 txHash) {
        if (transactions[txHash].approvals == 0) {
            revert TxNotFound(txHash);
        }
        _;
    }

    /// @notice Ensures that a transaction has not been executed
    modifier txNotExecuted(bytes32 txHash) {
        if (transactions[txHash].executed) {
            revert TxAlreadyExecuted(txHash);
        }
        _;
    }

    // =================== Functions ===================

    /// @notice Initializes the contract with the deployer as the first owner
    constructor() {
        isOwner[msg.sender] = true;
    }

    /**
     * @notice Invite a new owner
     * @param user Address of the invited owner
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

    /**
     * @notice Accept an ownership invitation
     */
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

    /**
     * @notice Renounce ownership
     * @dev At least one owner must remain
     */
    function renounceOwnership() external onlyOwner {
        require(minimumApprovals > 1, "min 1 owner is required");

        delete isOwner[msg.sender];
        minimumApprovals--;

        emit OwnerRenounced(msg.sender);
    }

    /**
     * @notice Submit a new transaction
     * @param recipient Address to which the transaction sends value
     * @param value Amount of native token to send
     * @param data Additional data payload
     * @return txHash Hash of the submitted transaction
     */
    function submitTransaction(address recipient, uint256 value, bytes calldata data)
        external
        onlyOwner
        returns (bytes32)
    {
        if (recipient == address(this)) {
            revert InvalidParameter("recipient");
        }

        bytes32 txHash = getTxHash(recipient, value, data, nonce);
        Transaction memory _tx = transactions[txHash];

        if (_tx.executed) {
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

        return txHash;
    }

    /**
     * @notice Approve a submitted transaction
     * @param txHash Transaction hash
     */
    function approveTransaction(bytes32 txHash)
        external
        onlyOwner
        txExists(txHash)
        txNotExecuted(txHash)
    {
        if (approvedBy[txHash][msg.sender]) {
            revert TxAlreadyApproved(txHash, msg.sender);
        }

        approvedBy[txHash][msg.sender] = true;
        transactions[txHash].approvals++;

        emit TransactionApproved(txHash, msg.sender);
    }

    /**
     * @notice Unapprove a previously approved transaction
     * @param txHash Transaction hash
     */
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

    /**
     * @notice Execute a fully approved transaction
     * @param txHash Transaction hash
     */
    function executeTransaction(bytes32 txHash)
        external
        onlyOwner
        txExists(txHash)
        txNotExecuted(txHash)
    {
        Transaction memory _tx = transactions[txHash];

        if (_tx.approvals < minimumApprovals) {
            revert TxNotEnoughApprovals(txHash, _tx.approvals, minimumApprovals);
        }

        transactions[txHash].executed = true;

        // CEI pattern, safe from reentrancy
        (bool success, bytes memory result) = _tx.to.call{ value: _tx.value }(_tx.data);
        if (!success) revert TxFailed(txHash, result);

        emit TransactionExecuted(
            _tx.to, _tx.value, _tx.data, _tx.approvals, txHash, msg.sender
        );
    }

    /**
     * @notice Compute transaction hash
     * @param recipient Address to send to
     * @param value Value to send
     * @param data Call data
     * @param _nonce Transaction nonce
     * @return Hash of the transaction
     */
    function getTxHash(
        address recipient,
        uint256 value,
        bytes calldata data,
        uint256 _nonce
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(recipient, value, data, _nonce));
    }

    /**
     * @notice Get transaction details by hash
     * @param txHash Transaction hash
     * @return recipient Transaction recipient
     * @return value Transaction value
     * @return data Transaction call data
     * @return approvals Number of approvals
     * @return executed Execution status
     */
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

    /**
     * @notice Get the current contract balance
     * @return Contract balance in wei
     */
    function balance() public view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable { }

    fallback() external payable { }
}
