/**
 *Submitted for verification at Etherscan.io on 2025-05-28
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IERC20
 * @dev Interface for the ERC20 standard
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external view returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @title Vaultec Core
 * @dev Handles vault creation, deposits, and withdrawals with timestamp tracking and transaction history
 */
contract VaultecCore {
    address public owner;
    // Multiple trading contracts support
    mapping(address => bool) public authorizedTradingContracts;
    uint256 public totalTradingContracts;
    uint256 public totalPersonalVaults;
    uint256 public totalCommunityVaults;
    uint256 public totalVaultBalance; // Total ETH balance across all vaults
    
    // Constants
    address constant ETH_ADDRESS = address(0);
    
    // Structs
    struct PersonalVault {
        uint256 vaultId; // Added vaultId for personal vaults
        address owner;
        mapping(address => uint256) tokenBalances; // token address => balance
        bool exists;
        uint256 createdAt; // Timestamp when vault was created
    }

    // Update the PersonalTransactionHistory struct to include first deposit tracking
    struct PersonalTransactionHistory {
        uint256 totalDeposited; // Total amount deposited (ETH equivalent)
        uint256 totalWithdrawn; // Total amount withdrawn (ETH equivalent)
        uint256 transactionCount; // Number of transactions
        uint256 lastTransactionAt; // Last transaction timestamp
        uint256 firstDepositAmount; // Amount of first deposit
        uint256 firstDepositTimestamp; // Timestamp of first deposit
    }
    
    // Update the MemberTransactionHistory struct to include first deposit tracking
    struct MemberTransactionHistory {
        uint256 totalDeposited; // Total amount deposited by member
        uint256 totalWithdrawn; // Total amount withdrawn by member
        uint256 transactionCount; // Number of transactions
        uint256 lastTransactionAt; // Last transaction timestamp
        uint256 firstDepositAmount; // Amount of first deposit
        uint256 firstDepositTimestamp; // Timestamp of first deposit
    }
    
    struct Member {
        address memberAddress;
        uint256 initialDeposit; // Initial ETH value deposited
        uint256 sharePercentage; // Calculated share percentage (scaled by 10000, so 1% = 100)
        bool isAdmin;
        bool exists;
        uint256 joinedAt; // Timestamp when member joined
        uint256 lastDepositAt; // Timestamp of last deposit
    }

    
    struct JoinRequest {
        address applicant;
        bool exists;
        bool processed;
        bool accepted;
        uint256 requestedAt; // Timestamp when request was made
        uint256 processedAt; // Timestamp when request was processed
    }
    
    struct CommunityVault {
        address leader;
        string name;
        uint256 totalMembers;
        uint256 totalBalance; // Total ETH value in the vault
        mapping(address => Member) members;
        mapping(address => JoinRequest) joinRequests;
        address[] memberList;
        address[] joinRequestList;
        mapping(address => uint256) tokenBalances; // token address => balance
        bool exists;
        uint256 createdAt; // Timestamp when vault was created
    }

    struct TransactionRecord {
        address user;
        address token;
        uint256 amount;
        bool isDeposit; // true for deposit, false for withdrawal
        bool isPersonal; // true for personal vault, false for community vault
        uint256 vaultId;
        uint256 timestamp;
    }
    
    // Mappings
    mapping(address => PersonalVault) public personalVaults;
    mapping(uint256 => address) public personalVaultOwners; // vaultId => owner address
    mapping(address => PersonalTransactionHistory) public personalTransactionHistory;
    mapping(uint256 => CommunityVault) public communityVaults;
    mapping(uint256 => mapping(address => MemberTransactionHistory)) public communityTransactionHistory; // vaultId => member => history
    mapping(address => uint256[]) public userCommunityVaults; // User address => array of community vault IDs they belong to
    
    // Transaction history arrays
    TransactionRecord[] public allTransactions;
    mapping(address => uint256[]) public userTransactionIds; // user => transaction IDs
    mapping(uint256 => uint256[]) public vaultTransactionIds; // vaultId => transaction IDs
    
    // Events with timestamps
    event PersonalVaultCreated(address indexed owner, uint256 indexed vaultId, uint256 timestamp);
    event CommunityVaultCreated(uint256 indexed vaultId, address indexed leader, string name, uint256 timestamp);
    event JoinRequestSubmitted(uint256 indexed vaultId, address indexed applicant, uint256 timestamp);
    event JoinRequestProcessed(uint256 indexed vaultId, address indexed applicant, bool accepted, uint256 timestamp);
    event Deposit(address indexed user, address indexed token, uint256 amount, bool isPersonal, uint256 vaultId, uint256 timestamp);
    event Withdrawal(address indexed user, address indexed token, uint256 amount, bool isPersonal, uint256 vaultId, uint256 timestamp);
    event AdminAdded(uint256 indexed vaultId, address indexed admin, uint256 timestamp);
    event AdminRemoved(uint256 indexed vaultId, address indexed admin, uint256 timestamp);
    event TradingContractAdded(address indexed tradingContract, uint256 timestamp);
    event TradingContractRemoved(address indexed tradingContract, uint256 timestamp);
    event TokensReceived(uint256 indexed vaultId, address indexed token, uint256 amount, bool isPersonal, uint256 timestamp);
    event DebugLog(string message, uint256 value);
    event TransactionRecorded(
        uint256 indexed transactionId,
        address indexed user,
        address indexed token,
        uint256 amount,
        bool isDeposit,
        bool isPersonal,
        uint256 vaultId,
        uint256 timestamp
    );
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier personalVaultExists() {
        require(personalVaults[msg.sender].exists, "Personal vault does not exist");
        _;
    }
    
    modifier personalVaultExistsById(uint256 vaultId) {
        address vaultOwner = personalVaultOwners[vaultId];
        require(vaultOwner != address(0), "Personal vault with this ID does not exist");
        require(personalVaults[vaultOwner].exists, "Personal vault does not exist");
        _;
    }
    
    modifier onlyPersonalVaultOwner(uint256 vaultId) {
        address vaultOwner = personalVaultOwners[vaultId];
        require(vaultOwner == msg.sender, "Only vault owner can call this function");
        _;
    }
    
    modifier communityVaultExists(uint256 vaultId) {
        require(communityVaults[vaultId].exists, "Community vault does not exist");
        _;
    }
    
    modifier onlyVaultLeader(uint256 vaultId) {
        require(communityVaults[vaultId].leader == msg.sender, "Only vault leader can call this function");
        _;
    }
    
    modifier onlyVaultAdmin(uint256 vaultId) {
        require(
            communityVaults[vaultId].leader == msg.sender || 
            (communityVaults[vaultId].members[msg.sender].exists && communityVaults[vaultId].members[msg.sender].isAdmin),
            "Only vault leader or admin can call this function"
        );
        _;
    }
    
    modifier onlyVaultMember(uint256 vaultId) {
        require(communityVaults[vaultId].members[msg.sender].exists, "Only vault member can call this function");
        _;
    }
    
    modifier onlyTradingContract() {
        require(authorizedTradingContracts[msg.sender], "Only authorized trading contract can call this function");
        _;
    }
    
    // Constructor
    constructor() {
        owner = msg.sender;
    }
    
    // External functions
    
    /**
     * @dev Add an authorized trading contract
     * @param _tradingContract The address of the trading contract to authorize
     */
    function addTradingContract(address _tradingContract) external onlyOwner {
        require(_tradingContract != address(0), "Invalid address");
        require(!authorizedTradingContracts[_tradingContract], "Already authorized");
        
        authorizedTradingContracts[_tradingContract] = true;
        totalTradingContracts++;
        
        emit TradingContractAdded(_tradingContract, block.timestamp);
    }

    /**
     * @dev Remove an authorized trading contract
     * @param _tradingContract The address of the trading contract to remove
     */
    function removeTradingContract(address _tradingContract) external onlyOwner {
        require(authorizedTradingContracts[_tradingContract], "Not authorized");
        
        authorizedTradingContracts[_tradingContract] = false;
        totalTradingContracts--;
        
        emit TradingContractRemoved(_tradingContract, block.timestamp);
    }

    /**
     * @dev Check if an address is an authorized trading contract
     * @param _address The address to check
     * @return Whether the address is authorized
     */
    function isTradingContract(address _address) external view returns (bool) {
        return authorizedTradingContracts[_address];
    }
    
    /**
     * @dev Create a personal vault
     * @return vaultId The ID of the created personal vault
     */
    function createPersonalVault() external returns (uint256 vaultId) {
        require(!personalVaults[msg.sender].exists, "Personal vault already exists");
        
        vaultId = totalPersonalVaults;
        uint256 currentTime = block.timestamp;
        
        PersonalVault storage newVault = personalVaults[msg.sender];
        newVault.vaultId = vaultId;
        newVault.owner = msg.sender;
        newVault.exists = true;
        newVault.createdAt = currentTime;
        
        // Map the vault ID to the owner
        personalVaultOwners[vaultId] = msg.sender;
        
        // Initialize transaction history
        PersonalTransactionHistory storage history = personalTransactionHistory[msg.sender];
        history.totalDeposited = 0;
        history.totalWithdrawn = 0;
        history.transactionCount = 0;
        history.lastTransactionAt = currentTime;
        history.firstDepositAmount = 0;
        history.firstDepositTimestamp = 0;
        
        totalPersonalVaults++;
        
        emit PersonalVaultCreated(msg.sender, vaultId, currentTime);
        return vaultId;
    }
    
    /**
     * @dev Create a community vault
     * @param name The name of the community vault
     * @return vaultId The ID of the created community vault
     */
    function createCommunityVault(string memory name) external returns (uint256 vaultId) {
        vaultId = totalCommunityVaults;
        uint256 currentTime = block.timestamp;
        
        CommunityVault storage newVault = communityVaults[vaultId];
        newVault.leader = msg.sender;
        newVault.name = name;
        newVault.exists = true;
        newVault.createdAt = currentTime;
        
        // Add creator as first member and admin
        Member storage leaderMember = newVault.members[msg.sender];
        leaderMember.memberAddress = msg.sender;
        leaderMember.initialDeposit = 0;
        leaderMember.sharePercentage = 0;
        leaderMember.isAdmin = true;
        leaderMember.exists = true;
        leaderMember.joinedAt = currentTime;
        leaderMember.lastDepositAt = 0;
        
        newVault.memberList.push(msg.sender);
        newVault.totalMembers = 1;
        
        // Add vault ID to user's list
        userCommunityVaults[msg.sender].push(vaultId);
        
        // Initialize transaction history for leader
        MemberTransactionHistory storage history = communityTransactionHistory[vaultId][msg.sender];
        history.totalDeposited = 0;
        history.totalWithdrawn = 0;
        history.transactionCount = 0;
        history.lastTransactionAt = currentTime;
        history.firstDepositAmount = 0;
        history.firstDepositTimestamp = 0;
        
        totalCommunityVaults++;
        
        emit CommunityVaultCreated(vaultId, msg.sender, name, currentTime);
        return vaultId;
    }
    
    /**
     * @dev Apply to join a community vault
     * @param vaultId The ID of the community vault
     */
    function applyToJoinCommunityVault(uint256 vaultId) external communityVaultExists(vaultId) {
        require(
            !communityVaults[vaultId].joinRequests[msg.sender].exists || 
            (communityVaults[vaultId].joinRequests[msg.sender].processed && 
             !communityVaults[vaultId].joinRequests[msg.sender].accepted),
            "Join request already submitted or pending"
        );
        
        uint256 currentTime = block.timestamp;
        
        JoinRequest storage request = communityVaults[vaultId].joinRequests[msg.sender];
        request.applicant = msg.sender;
        request.exists = true;
        request.processed = false;
        request.requestedAt = currentTime;
        request.processedAt = 0;
        
        // If this is a reapplication, add to the list again
        if (communityVaults[vaultId].joinRequests[msg.sender].processed) {
            communityVaults[vaultId].joinRequestList.push(msg.sender);
        }
        
        communityVaults[vaultId].joinRequestList.push(msg.sender);
        
        emit JoinRequestSubmitted(vaultId, msg.sender, currentTime);
    }
    
    /**
     * @dev Process a join request (accept or reject)
     * @param vaultId The ID of the community vault
     * @param applicant The address of the applicant
     * @param accept Whether to accept the request
     */
    function processJoinRequest(uint256 vaultId, address applicant, bool accept) 
        external 
        communityVaultExists(vaultId) 
        onlyVaultAdmin(vaultId) 
    {
        require(communityVaults[vaultId].joinRequests[applicant].exists, "Join request does not exist");
        require(!communityVaults[vaultId].joinRequests[applicant].processed, "Join request already processed");
        
        uint256 currentTime = block.timestamp;
        
        communityVaults[vaultId].joinRequests[applicant].processed = true;
        communityVaults[vaultId].joinRequests[applicant].accepted = accept;
        communityVaults[vaultId].joinRequests[applicant].processedAt = currentTime;
        
        if (accept) {
            // Add applicant as member
            Member storage newMember = communityVaults[vaultId].members[applicant];
            newMember.memberAddress = applicant;
            newMember.initialDeposit = 0;
            newMember.sharePercentage = 0;
            newMember.isAdmin = false;
            newMember.exists = true;
            newMember.joinedAt = currentTime;
            newMember.lastDepositAt = 0;
            
            communityVaults[vaultId].memberList.push(applicant);
            communityVaults[vaultId].totalMembers++;
            
            // Add vault ID to user's list
            userCommunityVaults[applicant].push(vaultId);
            
            // Initialize transaction history for new member
            MemberTransactionHistory storage history = communityTransactionHistory[vaultId][applicant];
            history.totalDeposited = 0;
            history.totalWithdrawn = 0;
            history.transactionCount = 0;
            history.lastTransactionAt = currentTime;
            history.firstDepositAmount = 0;
            history.firstDepositTimestamp = 0;
        }
        
        emit JoinRequestProcessed(vaultId, applicant, accept, currentTime);
    }
    
    /**
     * @dev Add an admin to a community vault
     * @param vaultId The ID of the community vault
     * @param admin The address of the new admin
     */
    function addAdmin(uint256 vaultId, address admin) 
        external 
        communityVaultExists(vaultId) 
        onlyVaultLeader(vaultId) 
    {
        require(communityVaults[vaultId].members[admin].exists, "Address is not a member of this vault");
        require(!communityVaults[vaultId].members[admin].isAdmin, "Address is already an admin");
        
        communityVaults[vaultId].members[admin].isAdmin = true;
        
        emit AdminAdded(vaultId, admin, block.timestamp);
    }
    
    /**
     * @dev Remove an admin from a community vault
     * @param vaultId The ID of the community vault
     * @param admin The address of the admin to remove
     */
    function removeAdmin(uint256 vaultId, address admin) 
        external 
        communityVaultExists(vaultId) 
        onlyVaultLeader(vaultId) 
    {
        require(communityVaults[vaultId].members[admin].exists, "Address is not a member of this vault");
        require(communityVaults[vaultId].members[admin].isAdmin, "Address is not an admin");
        require(admin != communityVaults[vaultId].leader, "Cannot remove leader as admin");
        
        communityVaults[vaultId].members[admin].isAdmin = false;
        
        emit AdminRemoved(vaultId, admin, block.timestamp);
    }
    
    /**
     * @dev Deposit ETH to personal vault
     * @param vaultId The ID of the personal vault
     */
    function depositETHToPersonalVault(uint256 vaultId) 
        external 
        payable 
        personalVaultExistsById(vaultId) 
        onlyPersonalVaultOwner(vaultId) 
    {
        require(msg.value > 0, "Amount must be greater than 0");
        
        uint256 currentTime = block.timestamp;
        
        personalVaults[msg.sender].tokenBalances[ETH_ADDRESS] += msg.value;
        totalVaultBalance += msg.value;
        
        // Update transaction history
        PersonalTransactionHistory storage history = personalTransactionHistory[msg.sender];
        
        // Track first deposit
        if (history.firstDepositTimestamp == 0) {
            history.firstDepositAmount = msg.value;
            history.firstDepositTimestamp = currentTime;
        }
        
        history.totalDeposited += msg.value;
        history.transactionCount++;
        history.lastTransactionAt = currentTime;
        
        // Record transaction
        _recordTransaction(msg.sender, ETH_ADDRESS, msg.value, true, true, vaultId, currentTime);
        
        emit Deposit(msg.sender, ETH_ADDRESS, msg.value, true, vaultId, currentTime);
    }
    
    /**
     * @dev Deposit ERC20 token to personal vault
     * @param vaultId The ID of the personal vault
     * @param token The address of the ERC20 token
     * @param amount The amount to deposit
     */
    function depositERC20ToPersonalVault(uint256 vaultId, address token, uint256 amount) 
        external 
        personalVaultExistsById(vaultId) 
        onlyPersonalVaultOwner(vaultId) 
    {
        require(token != ETH_ADDRESS, "Use depositETHToPersonalVault for ETH");
        require(amount > 0, "Amount must be greater than 0");
        
        uint256 currentTime = block.timestamp;
        
        IERC20 tokenContract = IERC20(token);
        require(tokenContract.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        personalVaults[msg.sender].tokenBalances[token] += amount;
        
        // Update transaction history
        PersonalTransactionHistory storage history = personalTransactionHistory[msg.sender];
        
        // Track first deposit (if no ETH deposit was made first)
        if (history.firstDepositTimestamp == 0) {
            history.firstDepositAmount = amount; // Note: This is in token units, not ETH equivalent
            history.firstDepositTimestamp = currentTime;
        }
        
        history.totalDeposited += amount; // Note: This is in token units, not ETH equivalent
        history.transactionCount++;
        history.lastTransactionAt = currentTime;
        
        // Record transaction
        _recordTransaction(msg.sender, token, amount, true, true, vaultId, currentTime);
        
        emit Deposit(msg.sender, token, amount, true, vaultId, currentTime);
    }
    
    /**
     * @dev Deposit ETH to community vault
     * @param vaultId The ID of the community vault
     */
    function depositETHToCommunityVault(uint256 vaultId) 
        external 
        payable 
        communityVaultExists(vaultId) 
        onlyVaultMember(vaultId) 
    {
        require(msg.value > 0, "Amount must be greater than 0");
        
        uint256 currentTime = block.timestamp;
        CommunityVault storage vault = communityVaults[vaultId];
        Member storage member = vault.members[msg.sender];
        
        // Update member's initial deposit and share percentage
        uint256 newTotalBalance = vault.totalBalance + msg.value;
        
        // If this is the member's first deposit, set initial deposit
        if (member.initialDeposit == 0) {
            member.initialDeposit = msg.value;
            member.sharePercentage = (msg.value * 10000) / newTotalBalance;
        } else {
            // Update member's share percentage
            uint256 newMemberDeposit = member.initialDeposit + msg.value;
            member.initialDeposit = newMemberDeposit;
            member.sharePercentage = (newMemberDeposit * 10000) / newTotalBalance;
        }
        
        // Update last deposit timestamp
        member.lastDepositAt = currentTime;
        
        // Update vault balance
        vault.tokenBalances[ETH_ADDRESS] += msg.value;
        vault.totalBalance = newTotalBalance;
        totalVaultBalance += msg.value;
        
        // Update transaction history
        MemberTransactionHistory storage history = communityTransactionHistory[vaultId][msg.sender];
        
        // Track first deposit
        if (history.firstDepositTimestamp == 0) {
            history.firstDepositAmount = msg.value;
            history.firstDepositTimestamp = currentTime;
        }
        
        history.totalDeposited += msg.value;
        history.transactionCount++;
        history.lastTransactionAt = currentTime;
        
        // Record transaction
        _recordTransaction(msg.sender, ETH_ADDRESS, msg.value, true, false, vaultId, currentTime);
        
        // Recalculate share percentages for all members
        recalculateSharePercentages(vaultId);
        
        emit Deposit(msg.sender, ETH_ADDRESS, msg.value, false, vaultId, currentTime);
    }
    
    /**
     * @dev Deposit ERC20 token to community vault
     * @param vaultId The ID of the community vault
     * @param token The address of the ERC20 token
     * @param amount The amount to deposit
     */
    function depositERC20ToCommunityVault(uint256 vaultId, address token, uint256 amount) 
        external 
        communityVaultExists(vaultId) 
        onlyVaultMember(vaultId) 
    {
        require(token != ETH_ADDRESS, "Use depositETHToCommunityVault for ETH");
        require(amount > 0, "Amount must be greater than 0");
        
        uint256 currentTime = block.timestamp;
        
        IERC20 tokenContract = IERC20(token);
        require(tokenContract.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        communityVaults[vaultId].tokenBalances[token] += amount;
        
        // Update transaction history
        MemberTransactionHistory storage history = communityTransactionHistory[vaultId][msg.sender];
        
        // Track first deposit (if no ETH deposit was made first)
        if (history.firstDepositTimestamp == 0) {
            history.firstDepositAmount = amount; // Note: This is in token units, not ETH equivalent
            history.firstDepositTimestamp = currentTime;
        }
        
        history.totalDeposited += amount; // Note: This is in token units, not ETH equivalent
        history.transactionCount++;
        history.lastTransactionAt = currentTime;
        
        // Record transaction
        _recordTransaction(msg.sender, token, amount, true, false, vaultId, currentTime);
        
        emit Deposit(msg.sender, token, amount, false, vaultId, currentTime);
    }
    
    /**
     * @dev Withdraw ETH from personal vault
     * @param vaultId The ID of the personal vault
     * @param amount The amount to withdraw
     */
    function withdrawETHFromPersonalVault(uint256 vaultId, uint256 amount) 
        external 
        personalVaultExistsById(vaultId) 
        onlyPersonalVaultOwner(vaultId) 
    {
        require(amount > 0, "Amount must be greater than 0");
        require(personalVaults[msg.sender].tokenBalances[ETH_ADDRESS] >= amount, "Insufficient balance");
        
        uint256 currentTime = block.timestamp;
        
        personalVaults[msg.sender].tokenBalances[ETH_ADDRESS] -= amount;
        totalVaultBalance -= amount;
        
        // Update transaction history
        PersonalTransactionHistory storage history = personalTransactionHistory[msg.sender];
        history.totalWithdrawn += amount;
        history.transactionCount++;
        history.lastTransactionAt = currentTime;
        
        // Record transaction
        _recordTransaction(msg.sender, ETH_ADDRESS, amount, false, true, vaultId, currentTime);
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit Withdrawal(msg.sender, ETH_ADDRESS, amount, true, vaultId, currentTime);
    }
    
    /**
     * @dev Withdraw ERC20 token from personal vault
     * @param vaultId The ID of the personal vault
     * @param token The address of the ERC20 token
     * @param amount The amount to withdraw
     */
    function withdrawERC20FromPersonalVault(uint256 vaultId, address token, uint256 amount) 
        external 
        personalVaultExistsById(vaultId) 
        onlyPersonalVaultOwner(vaultId) 
    {
        require(token != ETH_ADDRESS, "Use withdrawETHFromPersonalVault for ETH");
        require(amount > 0, "Amount must be greater than 0");
        require(personalVaults[msg.sender].tokenBalances[token] >= amount, "Insufficient balance");
        
        uint256 currentTime = block.timestamp;
        
        personalVaults[msg.sender].tokenBalances[token] -= amount;
        
        // Update transaction history
        PersonalTransactionHistory storage history = personalTransactionHistory[msg.sender];
        history.totalWithdrawn += amount; // Note: This is in token units, not ETH equivalent
        history.transactionCount++;
        history.lastTransactionAt = currentTime;
        
        // Record transaction
        _recordTransaction(msg.sender, token, amount, false, true, vaultId, currentTime);
        
        IERC20 tokenContract = IERC20(token);
        require(tokenContract.transfer(msg.sender, amount), "Transfer failed");
        
        emit Withdrawal(msg.sender, token, amount, true, vaultId, currentTime);
    }
    
    /**
     * @dev Withdraw ETH from community vault (partial withdrawal)
     * @param vaultId The ID of the community vault
     * @param amount The amount to withdraw
     */
    function withdrawETHFromCommunityVault(uint256 vaultId, uint256 amount) 
        external 
        communityVaultExists(vaultId) 
        onlyVaultMember(vaultId) 
    {
        require(amount > 0, "Amount must be greater than 0");
        
        CommunityVault storage vault = communityVaults[vaultId];
        Member storage member = vault.members[msg.sender];
        
        require(member.initialDeposit > 0, "No initial deposit");
        
        // Calculate maximum withdrawable amount based on share percentage
        uint256 maxWithdrawable = (vault.tokenBalances[ETH_ADDRESS] * member.sharePercentage) / 10000;
        require(amount <= maxWithdrawable, "Amount exceeds withdrawable balance");
        
        uint256 currentTime = block.timestamp;
        
        // Calculate the proportion of initial deposit being withdrawn
        uint256 depositReduction = (amount * member.initialDeposit) / maxWithdrawable;
        
        // Update member's initial deposit and vault balance
        member.initialDeposit -= depositReduction;
        vault.tokenBalances[ETH_ADDRESS] -= amount;
        vault.totalBalance -= amount;
        totalVaultBalance -= amount;
        
        // Update transaction history
        MemberTransactionHistory storage history = communityTransactionHistory[vaultId][msg.sender];
        history.totalWithdrawn += amount;
        history.transactionCount++;
        history.lastTransactionAt = currentTime;
        
        // Record transaction
        _recordTransaction(msg.sender, ETH_ADDRESS, amount, false, false, vaultId, currentTime);
        
        // Recalculate share percentages for all members
        recalculateSharePercentages(vaultId);
        
        // Transfer ETH to member
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit Withdrawal(msg.sender, ETH_ADDRESS, amount, false, vaultId, currentTime);
    }
    
    /**
     * @dev Withdraw ERC20 token from community vault (partial withdrawal)
     * @param vaultId The ID of the community vault
     * @param token The address of the ERC20 token
     * @param amount The amount to withdraw
     */
    function withdrawERC20FromCommunityVault(uint256 vaultId, address token, uint256 amount) 
        external 
        communityVaultExists(vaultId) 
        onlyVaultMember(vaultId) 
    {
        require(token != ETH_ADDRESS, "Use withdrawETHFromCommunityVault for ETH");
        require(amount > 0, "Amount must be greater than 0");
        
        CommunityVault storage vault = communityVaults[vaultId];
        Member storage member = vault.members[msg.sender];
        
        require(member.sharePercentage > 0, "No share percentage");
        
        // Calculate maximum withdrawable amount based on share percentage
        uint256 maxWithdrawable = (vault.tokenBalances[token] * member.sharePercentage) / 10000;
        require(amount <= maxWithdrawable, "Amount exceeds withdrawable balance");
        
        uint256 currentTime = block.timestamp;
        
        // Update vault balance
        vault.tokenBalances[token] -= amount;
        
        // Update transaction history
        MemberTransactionHistory storage history = communityTransactionHistory[vaultId][msg.sender];
        history.totalWithdrawn += amount; // Note: This is in token units, not ETH equivalent
        history.transactionCount++;
        history.lastTransactionAt = currentTime;
        
        // Record transaction
        _recordTransaction(msg.sender, token, amount, false, false, vaultId, currentTime);
        
        // Transfer token to member
        IERC20 tokenContract = IERC20(token);
        require(tokenContract.transfer(msg.sender, amount), "Transfer failed");
        
        emit Withdrawal(msg.sender, token, amount, false, vaultId, currentTime);
    }
    
    /**
     * @dev Transfer tokens from community vault to trading contract
     * @param vaultId The ID of the community vault
     * @param token The address of the token (ETH_ADDRESS for ETH)
     * @param amount The amount to transfer
     */
    function transferToTrading(uint256 vaultId, address token, uint256 amount) 
        external 
        onlyTradingContract 
        communityVaultExists(vaultId) 
        returns (bool) 
    {
        require(amount > 0, "Amount must be greater than 0");
        require(communityVaults[vaultId].tokenBalances[token] >= amount, "Insufficient balance");
        
        communityVaults[vaultId].tokenBalances[token] -= amount;
        
        if (token == ETH_ADDRESS) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            IERC20 tokenContract = IERC20(token);
            require(tokenContract.transfer(msg.sender, amount), "Transfer failed");
        }
        
        return true;
    }
    
    /**
     * @dev Transfer tokens from personal vault to trading contract
     * @param vaultId The ID of the personal vault
     * @param token The address of the token (ETH_ADDRESS for ETH)
     * @param amount The amount to transfer
     */
    function transferPersonalToTrading(uint256 vaultId, address token, uint256 amount) 
        external 
        onlyTradingContract 
        personalVaultExistsById(vaultId) 
        returns (bool) 
    {
        require(amount > 0, "Amount must be greater than 0");
        
        address vaultOwner = personalVaultOwners[vaultId];
        require(personalVaults[vaultOwner].tokenBalances[token] >= amount, "Insufficient balance");
        
        personalVaults[vaultOwner].tokenBalances[token] -= amount;
        
        if (token == ETH_ADDRESS) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            IERC20 tokenContract = IERC20(token);
            require(tokenContract.transfer(msg.sender, amount), "Transfer failed");
        }
        
        return true;
    }
    
    /**
     * @dev Receive tokens from trading contract for community vault
     * @param vaultId The ID of the community vault
     * @param token The address of the token (ETH_ADDRESS for ETH)
     * @param amount The amount received
     */
    function receiveFromTrading(uint256 vaultId, address token, uint256 amount) 
        external 
        payable 
        onlyTradingContract 
        communityVaultExists(vaultId) 
    {
        if (token == ETH_ADDRESS) {
            require(msg.value == amount, "Amount mismatch");
            communityVaults[vaultId].tokenBalances[ETH_ADDRESS] += amount;
            communityVaults[vaultId].totalBalance += amount;
            totalVaultBalance += amount;
        } else {
            // For ERC20 tokens, the trading contract should have already transferred the tokens
            // We just need to update our internal accounting
            
            emit DebugLog("Receiving ERC20 tokens from trading", amount);
            emit DebugLog("Token address", uint256(uint160(token)));
            emit DebugLog("Vault ID", vaultId);
            
            // Update the vault's token balance
            communityVaults[vaultId].tokenBalances[token] += amount;
        }
        
        emit TokensReceived(vaultId, token, amount, false, block.timestamp);
    }
    
    /**
     * @dev Receive tokens from trading contract for personal vault
     * @param vaultId The ID of the personal vault
     * @param token The address of the token (ETH_ADDRESS for ETH)
     * @param amount The amount received
     */
    function receivePersonalFromTrading(uint256 vaultId, address token, uint256 amount) 
        external 
        payable 
        onlyTradingContract 
        personalVaultExistsById(vaultId) 
    {
        address vaultOwner = personalVaultOwners[vaultId];
        
        if (token == ETH_ADDRESS) {
            require(msg.value == amount, "Amount mismatch");
            personalVaults[vaultOwner].tokenBalances[ETH_ADDRESS] += amount;
            totalVaultBalance += amount;
        } else {
            // For ERC20 tokens, the trading contract should have already transferred the tokens
            // We just need to update our internal accounting
            
            emit DebugLog("Receiving ERC20 tokens from trading for personal vault", amount);
            emit DebugLog("Token address", uint256(uint160(token)));
            emit DebugLog("Vault ID", vaultId);
            
            // Update the vault's token balance
            personalVaults[vaultOwner].tokenBalances[token] += amount;
        }
        
        emit TokensReceived(vaultId, token, amount, true, block.timestamp);
    }
    
    // Internal functions
    
    /**
     * @dev Record a transaction in the global transaction history
     * @param user The user making the transaction
     * @param token The token address
     * @param amount The amount
     * @param isDeposit Whether it's a deposit or withdrawal
     * @param isPersonal Whether it's a personal or community vault
     * @param vaultId The vault ID
     * @param timestamp The transaction timestamp
     */
    function _recordTransaction(
        address user,
        address token,
        uint256 amount,
        bool isDeposit,
        bool isPersonal,
        uint256 vaultId,
        uint256 timestamp
    ) internal {
        uint256 transactionId = allTransactions.length;
        
        TransactionRecord memory newTransaction = TransactionRecord({
            user: user,
            token: token,
            amount: amount,
            isDeposit: isDeposit,
            isPersonal: isPersonal,
            vaultId: vaultId,
            timestamp: timestamp
        });
        
        allTransactions.push(newTransaction);
        userTransactionIds[user].push(transactionId);
        vaultTransactionIds[vaultId].push(transactionId);
        
        emit TransactionRecorded(transactionId, user, token, amount, isDeposit, isPersonal, vaultId, timestamp);
    }
    
    /**
     * @dev Recalculate share percentages for all members of a community vault
     * @param vaultId The ID of the community vault
     */
    function recalculateSharePercentages(uint256 vaultId) internal {
        CommunityVault storage vault = communityVaults[vaultId];
        
        if (vault.totalBalance == 0) return;
        
        for (uint256 i = 0; i < vault.memberList.length; i++) {
            address memberAddress = vault.memberList[i];
            Member storage member = vault.members[memberAddress];
            
            if (member.initialDeposit > 0) {
                member.sharePercentage = (member.initialDeposit * 10000) / vault.totalBalance;
            }
        }
    }
    
    // View functions
    
    /**
     * @dev Get personal vault balance
     * @param vaultId The ID of the personal vault
     * @param token The address of the token (ETH_ADDRESS for ETH)
     * @return The balance of the token in the personal vault
     */
    function getPersonalVaultBalance(uint256 vaultId, address token) external view returns (uint256) {
        address vaultOwner = personalVaultOwners[vaultId];
        require(vaultOwner != address(0), "Personal vault with this ID does not exist");
        return personalVaults[vaultOwner].tokenBalances[token];
    }
    
    /**
     * @dev Get personal vault creation timestamp
     * @param vaultId The ID of the personal vault
     * @return The timestamp when the vault was created
     */
    function getPersonalVaultCreatedAt(uint256 vaultId) external view returns (uint256) {
        address vaultOwner = personalVaultOwners[vaultId];
        require(vaultOwner != address(0), "Personal vault with this ID does not exist");
        return personalVaults[vaultOwner].createdAt;
    }
    
    /**
     * @dev Get personal transaction history
     * @param user The address of the user
     * @return totalDeposited Total amount deposited
     * @return totalWithdrawn Total amount withdrawn
     * @return transactionCount Number of transactions
     * @return lastTransactionAt Last transaction timestamp
     */
    function getPersonalTransactionHistory(address user) external view returns (
        uint256 totalDeposited,
        uint256 totalWithdrawn,
        uint256 transactionCount,
        uint256 lastTransactionAt,
        uint256 firstDepositAmount,
        uint256 firstDepositTimestamp
    ) {
        PersonalTransactionHistory storage history = personalTransactionHistory[user];
        return (
            history.totalDeposited,
            history.totalWithdrawn,
            history.transactionCount,
            history.lastTransactionAt,
            history.firstDepositAmount,
            history.firstDepositTimestamp
        );
    }
    
    /**
     * @dev Get community vault balance
     * @param vaultId The ID of the community vault
     * @param token The address of the token (ETH_ADDRESS for ETH)
     * @return The balance of the token in the community vault
     */
    function getCommunityVaultBalance(uint256 vaultId, address token) external view returns (uint256) {
        return communityVaults[vaultId].tokenBalances[token];
    }
    
    /**
     * @dev Get community vault creation timestamp
     * @param vaultId The ID of the community vault
     * @return The timestamp when the vault was created
     */
    function getCommunityVaultCreatedAt(uint256 vaultId) external view returns (uint256) {
        return communityVaults[vaultId].createdAt;
    }
    
    /**
     * @dev Get community vault total balance
     * @param vaultId The ID of the community vault
     * @return The total ETH balance of the community vault
     */
    function getCommunityVaultTotalBalance(uint256 vaultId) external view returns (uint256) {
        return communityVaults[vaultId].totalBalance;
    }
    
    /**
     * @dev Get community vault member share percentage
     * @param vaultId The ID of the community vault
     * @param member The address of the member
     * @return The share percentage of the member (scaled by 10000)
     */
    function getMemberSharePercentage(uint256 vaultId, address member) external view returns (uint256) {
        return communityVaults[vaultId].members[member].sharePercentage;
    }
    
    /**
     * @dev Get community vault member initial deposit
     * @param vaultId The ID of the community vault
     * @param member The address of the member
     * @return The initial deposit of the member
     */
    function getMemberInitialDeposit(uint256 vaultId, address member) external view returns (uint256) {
        return communityVaults[vaultId].members[member].initialDeposit;
    }
    
    /**
     * @dev Get member timestamps
     * @param vaultId The ID of the community vault
     * @param member The address of the member
     * @return joinedAt The timestamp when member joined
     * @return lastDepositAt The timestamp of last deposit
     */
    function getMemberTimestamps(uint256 vaultId, address member) external view returns (uint256 joinedAt, uint256 lastDepositAt) {
        Member storage memberData = communityVaults[vaultId].members[member];
        return (memberData.joinedAt, memberData.lastDepositAt);
    }
    
    /**
     * @dev Get community member transaction history
     * @param vaultId The ID of the community vault
     * @param member The address of the member
     * @return totalDeposited Total amount deposited by member
     * @return totalWithdrawn Total amount withdrawn by member
     * @return transactionCount Number of transactions
     * @return lastTransactionAt Last transaction timestamp
     */
    function getCommunityMemberTransactionHistory(uint256 vaultId, address member) external view returns (
        uint256 totalDeposited,
        uint256 totalWithdrawn,
        uint256 transactionCount,
        uint256 lastTransactionAt,
        uint256 firstDepositAmount,
        uint256 firstDepositTimestamp
    ) {
        MemberTransactionHistory storage history = communityTransactionHistory[vaultId][member];
        return (
            history.totalDeposited,
            history.totalWithdrawn,
            history.transactionCount,
            history.lastTransactionAt,
            history.firstDepositAmount,
            history.firstDepositTimestamp
        );
    }
    
    /**
     * @dev Get withdrawable amount for a member in community vault
     * @param vaultId The ID of the community vault
     * @param member The address of the member
     * @param token The address of the token
     * @return The maximum withdrawable amount
     */
    function getWithdrawableAmount(uint256 vaultId, address member, address token) external view returns (uint256) {
        CommunityVault storage vault = communityVaults[vaultId];
        Member storage memberData = vault.members[member];
        
        if (memberData.sharePercentage == 0) return 0;
        
        return (vault.tokenBalances[token] * memberData.sharePercentage) / 10000;
    }
    
    /**
     * @dev Get community vault member list
     * @param vaultId The ID of the community vault
     * @return The list of members in the community vault
     */
    function getCommunityVaultMembers(uint256 vaultId) external view returns (address[] memory) {
        return communityVaults[vaultId].memberList;
    }
    
    /**
     * @dev Get community vault join request list
     * @param vaultId The ID of the community vault
     * @return The list of join requests for the community vault
     */
    function getJoinRequestList(uint256 vaultId) external view returns (address[] memory) {
        return communityVaults[vaultId].joinRequestList;
    }
    
    /**
     * @dev Get join request details with timestamps
     * @param vaultId The ID of the community vault
     * @param applicant The address of the applicant
     * @return exists Whether the join request exists
     * @return processed Whether the join request has been processed
     * @return accepted Whether the join request was accepted
     * @return requestedAt Timestamp when request was made
     * @return processedAt Timestamp when request was processed
     */
    function getJoinRequestDetails(uint256 vaultId, address applicant) 
        external 
        view 
        returns (bool exists, bool processed, bool accepted, uint256 requestedAt, uint256 processedAt) 
    {
        JoinRequest storage request = communityVaults[vaultId].joinRequests[applicant];
        return (request.exists, request.processed, request.accepted, request.requestedAt, request.processedAt);
    }
    
    /**
     * @dev Get community vaults for a user
     * @param user The address of the user
     * @return The list of community vault IDs the user belongs to
     */
    function getUserCommunityVaults(address user) external view returns (uint256[] memory) {
        return userCommunityVaults[user];
    }
    
    /**
     * @dev Check if an address is an admin of a community vault
     * @param vaultId The ID of the community vault
     * @param user The address to check
     * @return Whether the address is an admin
     */
    function isAdmin(uint256 vaultId, address user) external view returns (bool) {
        return communityVaults[vaultId].members[user].isAdmin;
    }
    
    /**
     * @dev Get the leader of a community vault
     * @param vaultId The ID of the community vault
     * @return The address of the leader
     */
    function getVaultLeader(uint256 vaultId) external view returns (address) {
        return communityVaults[vaultId].leader;
    }
    
    /**
     * @dev Get total number of members in a community vault
     * @param vaultId The ID of the community vault
     * @return The total number of members
     */
    function getTotalMembers(uint256 vaultId) external view returns (uint256) {
        return communityVaults[vaultId].totalMembers;
    }

    /**
     * @dev Get the name of a community vault
     * @param vaultId The ID of the community vault
     * @return The name of the community vault
     */
    function getVaultName(uint256 vaultId) external view returns (string memory) {
        return communityVaults[vaultId].name;
    }
    
    /**
     * @dev Check if a personal vault exists for a user
     * @param user The address of the user
     * @return Whether the personal vault exists
     */
    function checkPersonalVaultExists(address user) external view returns (bool) {
        return personalVaults[user].exists;
    }
    
    /**
     * @dev Get the ID of a personal vault for a user
     * @param user The address of the user
     * @return The ID of the personal vault
     */
    function getPersonalVaultId(address user) external view returns (uint256) {
        require(personalVaults[user].exists, "Personal vault does not exist");
        return personalVaults[user].vaultId;
    }
    
    /**
     * @dev Get the owner of a personal vault by ID
     * @param vaultId The ID of the personal vault
     * @return The address of the owner
     */
    function getPersonalVaultOwner(uint256 vaultId) external view returns (address) {
        address owner = personalVaultOwners[vaultId];
        require(owner != address(0), "Personal vault with this ID does not exist");
        return owner;
    }
    
    /**
     * @dev Check if a personal vault exists by ID
     * @param vaultId The ID of the personal vault
     * @return Whether the personal vault exists
     */
    function checkPersonalVaultExistsById(uint256 vaultId) external view returns (bool) {
        address owner = personalVaultOwners[vaultId];
        if (owner == address(0)) return false;
        return personalVaults[owner].exists;
    }
    
    /**
     * @dev Get user transaction IDs
     * @param user The address of the user
     * @return Array of transaction IDs for the user
     */
    function getUserTransactionIds(address user) external view returns (uint256[] memory) {
        return userTransactionIds[user];
    }
    
    /**
     * @dev Get vault transaction IDs
     * @param vaultId The ID of the vault
     * @return Array of transaction IDs for the vault
     */
    function getVaultTransactionIds(uint256 vaultId) external view returns (uint256[] memory) {
        return vaultTransactionIds[vaultId];
    }
    
    /**
     * @dev Get transaction details by ID
     * @param transactionId The ID of the transaction
     * @return user The user who made the transaction
     * @return token The token address
     * @return amount The transaction amount
     * @return isDeposit Whether it was a deposit
     * @return isPersonal Whether it was a personal vault transaction
     * @return vaultId The vault ID
     * @return timestamp The transaction timestamp
     */
    function getTransactionDetails(uint256 transactionId) external view returns (
        address user,
        address token,
        uint256 amount,
        bool isDeposit,
        bool isPersonal,
        uint256 vaultId,
        uint256 timestamp
    ) {
        require(transactionId < allTransactions.length, "Transaction does not exist");
        TransactionRecord storage transaction = allTransactions[transactionId];
        return (
            transaction.user,
            transaction.token,
            transaction.amount,
            transaction.isDeposit,
            transaction.isPersonal,
            transaction.vaultId,
            transaction.timestamp
        );
    }
    
    /**
     * @dev Get total number of transactions
     * @return The total number of transactions
     */
    function getTotalTransactions() external view returns (uint256) {
        return allTransactions.length;
    }
    
    /**
     * @dev Get comprehensive personal vault details
     * @param vaultId The ID of the personal vault
     * @return owner The address of the vault owner
     * @return exists Whether the vault exists
     * @return createdAt Timestamp when the vault was created
     * @return totalDeposited Total amount deposited to the vault
     * @return totalWithdrawn Total amount withdrawn from the vault
     * @return transactionCount Number of transactions
     * @return lastTransactionAt Last transaction timestamp
     * @return ethBalance Current ETH balance in the vault
     * @return firstDepositAmount Amount of first deposit
     * @return firstDepositTimestamp Timestamp of first deposit
     */
    function getPersonalVaultDetails(uint256 vaultId) external view returns (
        address owner,
        bool exists,
        uint256 createdAt,
        uint256 totalDeposited,
        uint256 totalWithdrawn,
        uint256 transactionCount,
        uint256 lastTransactionAt,
        uint256 ethBalance,
        uint256 firstDepositAmount,
        uint256 firstDepositTimestamp
    ) {
        address vaultOwner = personalVaultOwners[vaultId];
        require(vaultOwner != address(0), "Personal vault with this ID does not exist");
        
        PersonalVault storage vault = personalVaults[vaultOwner];
        PersonalTransactionHistory storage history = personalTransactionHistory[vaultOwner];
        
        return (
            vaultOwner,
            vault.exists,
            vault.createdAt,
            history.totalDeposited,
            history.totalWithdrawn,
            history.transactionCount,
            history.lastTransactionAt,
            vault.tokenBalances[ETH_ADDRESS],
            history.firstDepositAmount,
            history.firstDepositTimestamp
        );
    }
    
    /**
     * @dev Get comprehensive community vault details
     * @param vaultId The ID of the community vault
     * @return leader The address of the vault leader
     * @return name The name of the vault
     * @return exists Whether the vault exists
     * @return totalMembers Number of members in the vault
     * @return totalBalance Total ETH balance in the vault
     * @return createdAt Timestamp when the vault was created
     * @return ethBalance Current ETH balance in the vault
     * @return memberCount Number of members (same as totalMembers, for consistency)
     */
    function getCommunityVaultDetails(uint256 vaultId) external view returns (
        address leader,
        string memory name,
        bool exists,
        uint256 totalMembers,
        uint256 totalBalance,
        uint256 createdAt,
        uint256 ethBalance,
        uint256 memberCount
    ) {
        require(communityVaults[vaultId].exists, "Community vault does not exist");
        
        CommunityVault storage vault = communityVaults[vaultId];
        
        return (
            vault.leader,
            vault.name,
            vault.exists,
            vault.totalMembers,
            vault.totalBalance,
            vault.createdAt,
            vault.tokenBalances[ETH_ADDRESS],
            vault.memberList.length
        );
    }
    
    // Replace the getCommunityVaultMemberDetails function with these three separate functions:

    /**
     * @dev Get basic details for a community vault member
     * @param vaultId The ID of the community vault
     * @param memberAddress The address of the member
     * @return exists Whether the member exists in the vault
     * @return isAdmin Whether the member is an admin
     * @return initialDeposit Initial deposit amount
     * @return sharePercentage Share percentage (scaled by 10000)
     * @return joinedAt Timestamp when the member joined
     * @return lastDepositAt Timestamp of last deposit
     */
    function getCommunityVaultMemberBasicDetails(uint256 vaultId, address memberAddress) external view returns (
        bool exists,
        bool isAdmin,
        uint256 initialDeposit,
        uint256 sharePercentage,
        uint256 joinedAt,
        uint256 lastDepositAt
    ) {
        require(communityVaults[vaultId].exists, "Community vault does not exist");
        
        Member storage member = communityVaults[vaultId].members[memberAddress];
        
        return (
            member.exists,
            member.isAdmin,
            member.initialDeposit,
            member.sharePercentage,
            member.joinedAt,
            member.lastDepositAt
        );
    }

    /**
     * @dev Get transaction details for a community vault member
     * @param vaultId The ID of the community vault
     * @param memberAddress The address of the member
     * @return totalDeposited Total amount deposited by the member
     * @return totalWithdrawn Total amount withdrawn by the member
     * @return transactionCount Number of transactions by the member
     * @return lastTransactionAt Last transaction timestamp
     */
    function getCommunityVaultMemberTransactionDetails(uint256 vaultId, address memberAddress) external view returns (
        uint256 totalDeposited,
        uint256 totalWithdrawn,
        uint256 transactionCount,
        uint256 lastTransactionAt
    ) {
        require(communityVaults[vaultId].exists, "Community vault does not exist");
        require(communityVaults[vaultId].members[memberAddress].exists, "Member does not exist in this vault");
        
        MemberTransactionHistory storage history = communityTransactionHistory[vaultId][memberAddress];
        
        return (
            history.totalDeposited,
            history.totalWithdrawn,
            history.transactionCount,
            history.lastTransactionAt
        );
    }

    /**
     * @dev Get deposit-specific details for a community vault member
     * @param vaultId The ID of the community vault
     * @param memberAddress The address of the member
     * @return withdrawableEthAmount Maximum ETH amount the member can withdraw
     * @return firstDepositAmount Amount of first deposit
     * @return firstDepositTimestamp Timestamp of first deposit
     */
    function getCommunityVaultMemberDepositDetails(uint256 vaultId, address memberAddress) external view returns (
        uint256 withdrawableEthAmount,
        uint256 firstDepositAmount,
        uint256 firstDepositTimestamp
    ) {
        require(communityVaults[vaultId].exists, "Community vault does not exist");
        require(communityVaults[vaultId].members[memberAddress].exists, "Member does not exist in this vault");
        
        CommunityVault storage vault = communityVaults[vaultId];
        Member storage member = vault.members[memberAddress];
        MemberTransactionHistory storage history = communityTransactionHistory[vaultId][memberAddress];
        
        uint256 withdrawable = 0;
        if (member.sharePercentage > 0) {
            withdrawable = (vault.tokenBalances[ETH_ADDRESS] * member.sharePercentage) / 10000;
        }
        
        return (
            withdrawable,
            history.firstDepositAmount,
            history.firstDepositTimestamp
        );
    }
    
    /**
     * @dev Get token balance for a personal vault
     * @param vaultId The ID of the personal vault
     * @param token The address of the token
     * @return The balance of the token in the vault
     */
    function getPersonalVaultTokenBalance(uint256 vaultId, address token) external view returns (uint256) {
        address vaultOwner = personalVaultOwners[vaultId];
        require(vaultOwner != address(0), "Personal vault with this ID does not exist");
        return personalVaults[vaultOwner].tokenBalances[token];
    }
    
    /**
     * @dev Get token balance for a community vault
     * @param vaultId The ID of the community vault
     * @param token The address of the token
     * @return The balance of the token in the vault
     */
    function getCommunityVaultTokenBalance(uint256 vaultId, address token) external view returns (uint256) {
        require(communityVaults[vaultId].exists, "Community vault does not exist");
        return communityVaults[vaultId].tokenBalances[token];
    }
    
    /**
     * @dev Get withdrawable token amount for a community vault member
     * @param vaultId The ID of the community vault
     * @param memberAddress The address of the member
     * @param token The address of the token
     * @return The maximum amount of the token the member can withdraw
     */
    function getMemberWithdrawableTokenAmount(uint256 vaultId, address memberAddress, address token) external view returns (uint256) {
        require(communityVaults[vaultId].exists, "Community vault does not exist");
        
        CommunityVault storage vault = communityVaults[vaultId];
        Member storage member = vault.members[memberAddress];
        
        if (!member.exists || member.sharePercentage == 0) return 0;
        
        return (vault.tokenBalances[token] * member.sharePercentage) / 10000;
    }
    
    /**
     * @dev Get first deposit details for a personal vault user
     * @param user The address of the user
     * @return amount The amount of the first deposit
     * @return timestamp The timestamp of the first deposit
     */
    function getPersonalVaultFirstDeposit(address user) external view returns (
        uint256 amount,
        uint256 timestamp
    ) {
        require(personalVaults[user].exists, "Personal vault does not exist");
        PersonalTransactionHistory storage history = personalTransactionHistory[user];
        return (history.firstDepositAmount, history.firstDepositTimestamp);
    }
    
    /**
     * @dev Get first deposit details for a community vault member
     * @param vaultId The ID of the community vault
     * @param member The address of the member
     * @return amount The amount of the first deposit
     * @return timestamp The timestamp of the first deposit
     */
    function getCommunityMemberFirstDeposit(uint256 vaultId, address member) external view returns (
        uint256 amount,
        uint256 timestamp
    ) {
        require(communityVaults[vaultId].exists, "Community vault does not exist");
        require(communityVaults[vaultId].members[member].exists, "Member does not exist in this vault");
        
        MemberTransactionHistory storage history = communityTransactionHistory[vaultId][member];
        return (history.firstDepositAmount, history.firstDepositTimestamp);
    }
    
    /**
     * @dev Check if a user has made their first deposit to personal vault
     * @param user The address of the user
     * @return Whether the user has made their first deposit
     */
    function hasPersonalVaultFirstDeposit(address user) external view returns (bool) {
        if (!personalVaults[user].exists) return false;
        return personalTransactionHistory[user].firstDepositTimestamp > 0;
    }
    
    /**
     * @dev Check if a member has made their first deposit to community vault
     * @param vaultId The ID of the community vault
     * @param member The address of the member
     * @return Whether the member has made their first deposit
     */
    function hasCommunityMemberFirstDeposit(uint256 vaultId, address member) external view returns (bool) {
        if (!communityVaults[vaultId].exists) return false;
        if (!communityVaults[vaultId].members[member].exists) return false;
        return communityTransactionHistory[vaultId][member].firstDepositTimestamp > 0;
    }
    
    /**
     * @dev Get days since first deposit for personal vault
     * @param user The address of the user
     * @return Number of days since first deposit (0 if no deposit made)
     */
    function getDaysSincePersonalFirstDeposit(address user) external view returns (uint256) {
        if (!personalVaults[user].exists) return 0;
        uint256 firstDepositTime = personalTransactionHistory[user].firstDepositTimestamp;
        if (firstDepositTime == 0) return 0;
        return (block.timestamp - firstDepositTime) / 86400; // 86400 seconds in a day
    }
    
    /**
     * @dev Get days since first deposit for community vault member
     * @param vaultId The ID of the community vault
     * @param member The address of the member
     * @return Number of days since first deposit (0 if no deposit made)
     */
    function getDaysSinceCommunityFirstDeposit(uint256 vaultId, address member) external view returns (uint256) {
        if (!communityVaults[vaultId].exists) return 0;
        if (!communityVaults[vaultId].members[member].exists) return 0;
        uint256 firstDepositTime = communityTransactionHistory[vaultId][member].firstDepositTimestamp;
        if (firstDepositTime == 0) return 0;
        return (block.timestamp - firstDepositTime) / 86400; // 86400 seconds in a day
    }
    
    // Fallback and receive functions to accept ETH
    receive() external payable {}
    fallback() external payable {}
}
