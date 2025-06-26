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
 * @title IUniswapV2Router
 * @dev Interface for Uniswap V2 Router with fee-on-transfer token support
 */
interface IUniswapV2Router {
    function swapExactETHForTokens(
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external payable returns (uint[] memory amounts);
    
    function swapExactTokensForETH(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external returns (uint[] memory amounts);
    
    function swapExactTokensForTokens(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external returns (uint[] memory amounts);
    
    // Added fee-on-transfer supporting functions
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    
    function WETH() external pure returns (address);
    
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

/**
 * @title ICommunityVaultecCore
 * @dev Interface for Community Vaultec Core contract
 */
interface ICommunityVaultecCore {
    function transferToTrading(uint256 vaultId, address token, uint256 amount) external returns (bool);
    function receiveFromTrading(uint256 vaultId, address token, uint256 amount) external payable;
    function getVaultMembers(uint256 vaultId) external view returns (address[] memory); // Renamed from getCommunityVaultMembers
    function isVaultAdmin(uint256 vaultId, address user) external view returns (bool); // Renamed from isAdmin
    function getLeader(uint256 vaultId) external view returns (address); // Renamed from getVaultLeader
    function getMemberCount(uint256 vaultId) external view returns (uint256); // Renamed from getTotalMembers
}

/**
 * @title Vaultec Trading
 * @dev Handles trading operations for Vaultec vaults
 */
contract VaultecTrading {
    address public owner;
    address public communityVaultecCoreAddress;
    address public uniswapRouterAddress;
    
    // Constants
    address constant ETH_ADDRESS = address(0);
    uint256 public VOTING_THRESHOLD = 50; // 50% voting threshold
    
    // Structs
    enum ProposalType { ETH_TO_TOKEN, TOKEN_TO_ETH, TOKEN_TO_TOKEN }
    enum ProposalStatus { Active, Executed, Expired, Cancelled }
    
    struct Vote {
        bool hasVoted;
        bool inFavor;
    }
    
    struct TradeProposal {
        uint256 vaultId;
        address creator;
        ProposalType proposalType;
        address sourceToken;
        address targetToken;
        uint256 amount;
        uint256 minAmountOut;
        uint256 yesVotes;
        uint256 noVotes;
        mapping(address => Vote) votes;
        ProposalStatus status;
        bool exists;
        bool tokensRetrieved;
        uint256 amountReceived;
        bool hasFees;
    }

    struct TimeStamp {
        uint256 vaultId;
        uint256 createdAt;
        uint256 executedAt;
    }
    
    // Mappings
    mapping(uint256 => TradeProposal) public tradeProposals;
    mapping(uint256 => TimeStamp) public timeStamp;
    uint256 public totalProposals;
    mapping(address => bool) public tokenHasFees; // Track which tokens have transfer fees
    
    // Events
    event ProposalCreated(
        uint256 indexed proposalId, 
        uint256 indexed vaultId, 
        address indexed creator, 
        ProposalType proposalType,
        address sourceToken,
        address targetToken,
        uint256 amount,
        uint256 minAmountOut,
        bool hasFees
    );

    event ProposalCreatedTimestamp(
        uint256 indexed proposalId, 
        uint256 indexed vaultId, 
        uint256 createdAt,
        uint256 executedAt
    );
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool inFavor);
    event ProposalExecuted(uint256 indexed proposalId, uint256 indexed vaultId, uint256 amountOut);
    event ProposalExecutedTimeStamp(uint256 indexed proposalId, uint256 executedAt);
    event CoreAddressUpdated(address indexed newAddress);
    event RouterAddressUpdated(address indexed newAddress);
    event DebugLog(string message, uint256 value);
    event SwapExecuted(address sourceToken, address targetToken, uint256 amountIn, uint256 amountOut);
    event TokensRetrieved(uint256 indexed proposalId, address indexed token, uint256 amount);
    event TokenFeeStatusSet(address indexed token, bool hasFees);
    event ProposalCancelled(uint256 indexed proposalId, uint256 indexed vaultId, address indexed creator, uint256 timestamp);
    event ProposalEdited(
        uint256 indexed proposalId, 
        uint256 indexed vaultId, 
        address indexed creator,
        uint256 newAmount,
        uint256 newMinAmountOut,
        bool newHasFees,
        uint256 timestamp
    );
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier proposalExists(uint256 proposalId) {
        require(tradeProposals[proposalId].exists, "Proposal does not exist");
        _;
    }
    
    modifier onlyVaultMember(uint256 vaultId) {
        address[] memory members = ICommunityVaultecCore(communityVaultecCoreAddress).getVaultMembers(vaultId);
        bool isMember = false;
        
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] == msg.sender) {
                isMember = true;
                break;
            }
        }
        
        require(isMember, "Only vault member can call this function");
        _;
    }
    
    modifier onlyVaultAdminOrLeader(uint256 vaultId) {
        require(
            ICommunityVaultecCore(communityVaultecCoreAddress).isVaultAdmin(vaultId, msg.sender) || 
            ICommunityVaultecCore(communityVaultecCoreAddress).getLeader(vaultId) == msg.sender,
            "Only vault admin or leader can call this function"
        );
        _;
    }
    
    modifier onlyProposalCreator(uint256 proposalId) {
        require(tradeProposals[proposalId].creator == msg.sender, "Only proposal creator can call this function");
        _;
    }
    
    modifier onlyProposalAuthorized(uint256 proposalId) {
        uint256 vaultId = tradeProposals[proposalId].vaultId;
        require(
            tradeProposals[proposalId].creator == msg.sender || 
            ICommunityVaultecCore(communityVaultecCoreAddress).isVaultAdmin(vaultId, msg.sender) || 
            ICommunityVaultecCore(communityVaultecCoreAddress).getLeader(vaultId) == msg.sender || 
            msg.sender == address(this),
            "Only proposal creator, vault admin, or leader can call this function"
        );
        _;
    }
    
    // Constructor
    constructor() {
        owner = msg.sender;
    }
    
    // External functions
    
    /**
     * @dev Set the Vaultec Core contract address
     * @param _communityVaultecCoreAddress The address of the Vaultec Core contract
     */
    function setCommunityVaultecCoreAddress(address _communityVaultecCoreAddress) external onlyOwner {
        communityVaultecCoreAddress = _communityVaultecCoreAddress;
        emit CoreAddressUpdated(_communityVaultecCoreAddress);
    }
    
    /**
     * @dev Set the Uniswap Router contract address
     * @param _uniswapRouterAddress The address of the Uniswap Router contract
     */
    function setUniswapRouterAddress(address _uniswapRouterAddress) external onlyOwner {
        uniswapRouterAddress = _uniswapRouterAddress;
        emit RouterAddressUpdated(_uniswapRouterAddress);
    }
    
    /**
     * @dev Set whether a token has transfer fees
     * @param token The address of the token
     * @param hasFees Whether the token has transfer fees
     */
    function setTokenFeeStatus(address token, bool hasFees) external onlyOwner {
        require(token != ETH_ADDRESS, "Cannot set fee status for ETH");
        tokenHasFees[token] = hasFees;
        emit TokenFeeStatusSet(token, hasFees);
    }

    /**
     * @dev Set voting threshold
     */
     function setVotingThreshold(uint256 newThreshold) external onlyOwner {
        VOTING_THRESHOLD=newThreshold;
     }
    
    /**
     * @dev Create a trade proposal
     * @param vaultId The ID of the community vault
     * @param proposalType The type of the proposal (ETH_TO_TOKEN, TOKEN_TO_ETH, TOKEN_TO_TOKEN)
     * @param sourceToken The address of the source token (ETH_ADDRESS for ETH)
     * @param targetToken The address of the target token (ETH_ADDRESS for ETH)
     * @param amount The amount to trade
     * @param minAmountOut The minimum amount to receive
     * @param hasFees Whether the token has transfer fees
     */
    function createTradeProposal(
        uint256 vaultId,
        ProposalType proposalType,
        address sourceToken,
        address targetToken,
        uint256 amount,
        uint256 minAmountOut,
        bool hasFees
    ) 
        external 
        onlyVaultAdminOrLeader(vaultId) 
    {
        require(amount > 0, "Amount must be greater than 0");
        
        // Validate proposal type and tokens
        if (proposalType == ProposalType.ETH_TO_TOKEN) {
            require(sourceToken == ETH_ADDRESS, "Source token must be ETH");
            require(targetToken != ETH_ADDRESS, "Target token cannot be ETH");
        } else if (proposalType == ProposalType.TOKEN_TO_ETH) {
            require(sourceToken != ETH_ADDRESS, "Source token cannot be ETH");
            require(targetToken == ETH_ADDRESS, "Target token must be ETH");
        } else if (proposalType == ProposalType.TOKEN_TO_TOKEN) {
            require(sourceToken != ETH_ADDRESS, "Source token cannot be ETH");
            require(targetToken != ETH_ADDRESS, "Target token cannot be ETH");
            require(sourceToken != targetToken, "Source and target tokens cannot be the same");
        }
        
        uint256 proposalId = totalProposals;
        uint256 currentTime = block.timestamp;
        
        TradeProposal storage proposal = tradeProposals[proposalId];
        proposal.vaultId = vaultId;
        proposal.creator = msg.sender;
        proposal.proposalType = proposalType;
        proposal.sourceToken = sourceToken;
        proposal.targetToken = targetToken;
        proposal.amount = amount;
        proposal.minAmountOut = minAmountOut;
        proposal.status = ProposalStatus.Active;
        proposal.exists = true;
        proposal.tokensRetrieved = false;
        proposal.hasFees = hasFees;

        TimeStamp storage time = timeStamp[proposalId];
        time.vaultId = vaultId;
        time.createdAt = currentTime;
        time.executedAt = 0;
        
        // If the user didn't specify, use the stored value
        if (sourceToken != ETH_ADDRESS && !hasFees) {
            proposal.hasFees = tokenHasFees[sourceToken];
        }
        
        totalProposals++;
        
        emit ProposalCreated(
            proposalId,
            vaultId,
            msg.sender,
            proposalType,
            sourceToken,
            targetToken,
            amount,
            minAmountOut,
            proposal.hasFees
        );

        emit ProposalCreatedTimestamp(
            proposalId,
            vaultId,
            currentTime,
            0
        );
    }
    
    /**
     * @dev Vote on a trade proposal
     * @param proposalId The ID of the proposal
     * @param inFavor Whether the vote is in favor of the proposal
     */
    function voteOnProposal(uint256 proposalId, bool inFavor) 
        external 
        proposalExists(proposalId) 
        onlyVaultMember(tradeProposals[proposalId].vaultId) 
    {
        TradeProposal storage proposal = tradeProposals[proposalId];
        
        require(proposal.status == ProposalStatus.Active, "Proposal is not active");
        require(!proposal.votes[msg.sender].hasVoted, "Already voted");
        
        proposal.votes[msg.sender].hasVoted = true;
        proposal.votes[msg.sender].inFavor = inFavor;
        
        if (inFavor) {
            proposal.yesVotes++;
        } else {
            proposal.noVotes++;
        }
        
        emit VoteCast(proposalId, msg.sender, inFavor);
    }
    
    /**
     * @dev Execute a trade proposal
     * @param proposalId The ID of the proposal
     */
    function executeProposal(uint256 proposalId) 
        external 
        proposalExists(proposalId) 
        onlyProposalCreator(proposalId) 
    {
        TradeProposal storage proposal = tradeProposals[proposalId];
        TimeStamp storage time = timeStamp[proposalId];
        
        require(proposal.status == ProposalStatus.Active, "Proposal is not active");
        
        // Check if proposal has enough votes
        uint256 totalMembers = ICommunityVaultecCore(communityVaultecCoreAddress).getMemberCount(proposal.vaultId);
        uint256 requiredVotes = (totalMembers * VOTING_THRESHOLD) / 100;
        
        require(proposal.yesVotes >= requiredVotes, "Not enough yes votes");
        
        // Mark proposal as executed
        proposal.status = ProposalStatus.Executed;

        // Mark the execute timestamp
        uint256 executeTime = block.timestamp;
        time.executedAt = executeTime;
        
        emit DebugLog("Transferring from vault", proposal.amount);
        
        // Transfer tokens from vault to trading contract
        bool transferSuccess = ICommunityVaultecCore(communityVaultecCoreAddress).transferToTrading(
            proposal.vaultId,
            proposal.sourceToken,
            proposal.amount
        );
        require(transferSuccess, "Transfer from vault failed");
        
        emit DebugLog("Transfer successful", 1);
        
        // Execute trade based on proposal type
        uint256 amountOut;

        if (proposal.proposalType == ProposalType.ETH_TO_TOKEN) {
            emit DebugLog("Executing ETH to Token swap", proposal.amount);
            
            // Verify we have the ETH
            require(address(this).balance >= proposal.amount, "Insufficient ETH balance for swap");
            
            // Use fee-supporting function if the token has fees
            if (proposal.hasFees || tokenHasFees[proposal.targetToken]) {
                amountOut = _swapETHForTokensWithFees(
                    proposal.targetToken,
                    proposal.amount,
                    proposal.minAmountOut
                );
            } else {
                amountOut = _swapETHForTokens(
                    proposal.targetToken,
                    proposal.amount,
                    proposal.minAmountOut
                );
            }
            
            emit DebugLog("Swap completed, received", amountOut);
            
            // Verify we received the tokens
            uint256 tokenBalance = IERC20(proposal.targetToken).balanceOf(address(this));
            require(tokenBalance >= amountOut, "Token balance check failed");
            
            emit DebugLog("Token balance verified", tokenBalance);
            emit SwapExecuted(proposal.sourceToken, proposal.targetToken, proposal.amount, amountOut);
            emit ProposalExecuted(proposalId, proposal.vaultId, amountOut);
            
            // Store the amount received
            proposal.amountReceived = amountOut;

            //Send the token to VaultCore
            this.retrieveTokens(proposalId);
            
        } else if (proposal.proposalType == ProposalType.TOKEN_TO_ETH) {
            emit DebugLog("Executing Token to ETH swap", proposal.amount);
            
            // Verify we have the tokens
            uint256 tokenBalance = IERC20(proposal.sourceToken).balanceOf(address(this));
            require(tokenBalance >= proposal.amount, "Insufficient token balance for swap");
            
            emit DebugLog("Token balance verified", tokenBalance);
            
            // Use fee-supporting function if the token has fees
            if (proposal.hasFees || tokenHasFees[proposal.sourceToken]) {
                amountOut = _swapTokensForETHWithFees(
                    proposal.sourceToken,
                    proposal.amount,
                    proposal.minAmountOut
                );
            } else {
                amountOut = _swapTokensForETH(
                    proposal.sourceToken,
                    proposal.amount,
                    proposal.minAmountOut
                );
            }
            
            emit DebugLog("Swap completed, received ETH", amountOut);
            
            // Verify we received the ETH
            require(address(this).balance >= amountOut, "ETH balance check failed");
            
            emit DebugLog("ETH balance verified", address(this).balance);
            
            // Transfer ETH back to VaultecCore
            ICommunityVaultecCore(communityVaultecCoreAddress).receiveFromTrading{value: amountOut}(
                proposal.vaultId,
                ETH_ADDRESS,
                amountOut
            );
            
            emit DebugLog("VaultecCore updated", amountOut);
            emit SwapExecuted(proposal.sourceToken, proposal.targetToken, proposal.amount, amountOut);
            emit ProposalExecuted(proposalId, proposal.vaultId, amountOut);
            proposal.tokensRetrieved = true; // Mark as retrieved since ETH is automatically sent back
            
        } else if (proposal.proposalType == ProposalType.TOKEN_TO_TOKEN) {
            emit DebugLog("Executing Token to Token swap", proposal.amount);
            
            // Verify we have the source tokens
            uint256 sourceTokenBalance = IERC20(proposal.sourceToken).balanceOf(address(this));
            require(sourceTokenBalance >= proposal.amount, "Insufficient source token balance for swap");
            
            emit DebugLog("Source token balance verified", sourceTokenBalance);
            
            // Use fee-supporting function if either token has fees
            if (proposal.hasFees || tokenHasFees[proposal.sourceToken] || tokenHasFees[proposal.targetToken]) {
                amountOut = _swapTokensForTokensWithFees(
                    proposal.sourceToken,
                    proposal.targetToken,
                    proposal.amount,
                    proposal.minAmountOut
                );
            } else {
                amountOut = _swapTokensForTokens(
                    proposal.sourceToken,
                    proposal.targetToken,
                    proposal.amount,
                    proposal.minAmountOut
                );
            }
            
            emit DebugLog("Swap completed, received tokens", amountOut);
            
            // Verify we received the target tokens
            uint256 targetTokenBalance = IERC20(proposal.targetToken).balanceOf(address(this));
            require(targetTokenBalance >= amountOut, "Target token balance check failed");
            
            emit DebugLog("Target token balance verified", targetTokenBalance);
            emit SwapExecuted(proposal.sourceToken, proposal.targetToken, proposal.amount, amountOut);
            emit ProposalExecuted(proposalId, proposal.vaultId, amountOut);
            emit ProposalExecutedTimeStamp(proposalId, executeTime);

            // Store the amount received
            proposal.amountReceived = amountOut;

            //Send the token to VaultCore
            this.retrieveTokens(proposalId);
        }
    }
    
    /**
     * @dev Cancel a trade proposal
     * @param proposalId The ID of the proposal
     */
    function cancelProposal(uint256 proposalId) 
        external 
        proposalExists(proposalId) 
        onlyProposalCreator(proposalId) 
    {
        TradeProposal storage proposal = tradeProposals[proposalId];
        TimeStamp storage time = timeStamp[proposalId];
        
        require(proposal.status == ProposalStatus.Active, "Proposal is not active");
        
        // Mark proposal as cancelled
        proposal.status = ProposalStatus.Cancelled;
        time.executedAt = block.timestamp; // Use executedAt to track cancellation time
        
        emit ProposalCancelled(proposalId, proposal.vaultId, msg.sender, block.timestamp);
    }
    
    /**
     * @dev Edit a trade proposal
     * @param proposalId The ID of the proposal
     * @param newAmount The new amount to trade
     * @param newMinAmountOut The new minimum amount to receive
     * @param newHasFees Whether the token has transfer fees
     */
    function editProposal(
        uint256 proposalId,
        uint256 newAmount,
        uint256 newMinAmountOut,
        bool newHasFees
    ) 
        external 
        proposalExists(proposalId) 
        onlyProposalCreator(proposalId) 
    {
        TradeProposal storage proposal = tradeProposals[proposalId];
        
        require(proposal.status == ProposalStatus.Active, "Proposal is not active");
        require(newAmount > 0, "Amount must be greater than 0");
        
        // Update proposal parameters
        proposal.amount = newAmount;
        proposal.minAmountOut = newMinAmountOut;
        proposal.hasFees = newHasFees;
        
        // If the user didn't specify fees but the token is known to have fees, use stored value
        if (proposal.sourceToken != ETH_ADDRESS && !newHasFees) {
            proposal.hasFees = tokenHasFees[proposal.sourceToken];
        }
        
        emit ProposalEdited(
            proposalId,
            proposal.vaultId,
            msg.sender,
            newAmount,
            newMinAmountOut,
            proposal.hasFees,
            block.timestamp
        );
    }
    
    /**
     * @dev Retrieve tokens from a completed swap and transfer them to VaultecCore
     * @param proposalId The ID of the executed proposal
     */
    function retrieveTokens(uint256 proposalId) 
        external 
        proposalExists(proposalId) 
        onlyProposalAuthorized(proposalId) 
{
    TradeProposal storage proposal = tradeProposals[proposalId];
    
    require(proposal.status == ProposalStatus.Executed, "Proposal must be executed");
    require(!proposal.tokensRetrieved, "Tokens already retrieved");
    
    // For TOKEN_TO_ETH, tokens are automatically sent back in executeProposal
    require(
        proposal.proposalType == ProposalType.ETH_TO_TOKEN || 
        proposal.proposalType == ProposalType.TOKEN_TO_TOKEN, 
        "Not applicable for ETH output"
    );
    
    require(proposal.amountReceived > 0, "No amount received from swap");
    
    address tokenAddress = proposal.targetToken;
    uint256 amountToTransfer = proposal.amountReceived;
    
    // Check token balance in this contract
    uint256 tokenBalance = IERC20(tokenAddress).balanceOf(address(this));
    require(tokenBalance >= amountToTransfer, "Insufficient token balance");
    
    emit DebugLog("Retrieving tokens for proposal", proposalId);
    emit DebugLog("Amount to transfer", amountToTransfer);
    
    // Mark tokens as retrieved first to avoid reentrancy
    proposal.tokensRetrieved = true;
    
    // Transfer tokens directly to VaultecCore
    bool transferSuccess = IERC20(tokenAddress).transfer(communityVaultecCoreAddress, amountToTransfer);
    require(transferSuccess, "Token transfer to VaultecCore failed");
    
    emit DebugLog("Tokens transferred to VaultecCore", amountToTransfer);
    
    // Update VaultecCore records
    ICommunityVaultecCore(communityVaultecCoreAddress).receiveFromTrading(
        proposal.vaultId,
        tokenAddress,
        amountToTransfer
    );
    
    emit TokensRetrieved(proposalId, tokenAddress, amountToTransfer);
    emit DebugLog("Tokens successfully retrieved and vault updated", amountToTransfer);
}
    
    /**
     * @dev Emergency retrieve tokens for a specific token address
     * @param token The address of the token to retrieve
     * @param vaultId The ID of the vault to send tokens to
     */
    function emergencyRetrieveTokens(address token, uint256 vaultId) 
        external 
        onlyOwner 
    {
        require(token != ETH_ADDRESS, "Use emergencyRetrieveETH for ETH");
        
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        require(tokenBalance > 0, "No tokens to retrieve");
        
        // Transfer tokens to VaultecCore
        bool transferSuccess = IERC20(token).transfer(communityVaultecCoreAddress, tokenBalance);
        require(transferSuccess, "Token transfer to VaultecCore failed");
        
        // Update VaultecCore records
        ICommunityVaultecCore(communityVaultecCoreAddress).receiveFromTrading(
            vaultId,
            token,
            tokenBalance
        );
        
        emit DebugLog("Emergency tokens retrieved", tokenBalance);
    }
    
    /**
     * @dev Emergency retrieve ETH
     * @param vaultId The ID of the vault to send ETH to
     */
    function emergencyRetrieveETH(uint256 vaultId) 
        external 
        onlyOwner 
    {
        uint256 ethBalance = address(this).balance;
        require(ethBalance > 0, "No ETH to retrieve");
        
        // Transfer ETH to VaultecCore
        ICommunityVaultecCore(communityVaultecCoreAddress).receiveFromTrading{value: ethBalance}(
            vaultId,
            ETH_ADDRESS,
            ethBalance
        );
        
        emit DebugLog("Emergency ETH retrieved", ethBalance);
    }
    
    // Internal functions
    
    /**
     * @dev Swap ETH for tokens
     * @param tokenOut The address of the token to receive
     * @param amountIn The amount of ETH to swap
     * @param amountOutMin The minimum amount of tokens to receive
     * @return The amount of tokens received
     */
    function _swapETHForTokens(
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256) {
        IUniswapV2Router router = IUniswapV2Router(uniswapRouterAddress);
        
        // Create path
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = tokenOut;
        
        // Get initial balance to calculate exact amount received
        uint256 initialBalance = IERC20(tokenOut).balanceOf(address(this));
        
        emit DebugLog("Initial token balance", initialBalance);
        emit DebugLog("ETH amount for swap", amountIn);
        
        // Execute swap
        try router.swapExactETHForTokens{value: amountIn}(
            amountOutMin,
            path,
            address(this),
            block.timestamp + 1800 // 30 minutes hardcoded deadline
        ) returns (uint[] memory /* amounts */) {
            // Calculate actual amount received
            uint256 finalBalance = IERC20(tokenOut).balanceOf(address(this));
            uint256 amountReceived = finalBalance - initialBalance;
            
            emit DebugLog("Final token balance", finalBalance);
            emit DebugLog("Amount received", amountReceived);
            
            require(amountReceived >= amountOutMin, "Insufficient output amount");
            return amountReceived;
        } catch Error(string memory reason) {
            emit DebugLog("Swap failed with reason", 0);
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        } catch {
            emit DebugLog("Swap failed with unknown error", 0);
            revert("Swap failed with unknown error");
        }
    }
    
    /**
     * @dev Swap ETH for tokens with fee support
     * @param tokenOut The address of the token to receive
     * @param amountIn The amount of ETH to swap
     * @param amountOutMin The minimum amount of tokens to receive
     * @return The amount of tokens received
     */
    function _swapETHForTokensWithFees(
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256) {
        IUniswapV2Router router = IUniswapV2Router(uniswapRouterAddress);
        
        // Create path
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = tokenOut;
        
        // Get initial balance to calculate exact amount received
        uint256 initialBalance = IERC20(tokenOut).balanceOf(address(this));
        
        emit DebugLog("Initial token balance (with fees)", initialBalance);
        emit DebugLog("ETH amount for swap", amountIn);
        
        // Execute swap with fee support
        try router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOutMin,
            path,
            address(this),
            block.timestamp + 1800 // 30 minutes hardcoded deadline
        ) {
            // Calculate actual amount received
            uint256 finalBalance = IERC20(tokenOut).balanceOf(address(this));
            uint256 amountReceived = finalBalance - initialBalance;
            
            emit DebugLog("Final token balance", finalBalance);
            emit DebugLog("Amount received (with fees)", amountReceived);
            
            require(amountReceived >= amountOutMin, "Insufficient output amount");
            return amountReceived;
        } catch Error(string memory reason) {
            emit DebugLog("Swap with fees failed with reason", 0);
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        } catch {
            emit DebugLog("Swap with fees failed with unknown error", 0);
            revert("Swap failed with unknown error");
        }
    }
    
    /**
     * @dev Swap tokens for ETH
     * @param tokenIn The address of the token to swap
     * @param amountIn The amount of tokens to swap
     * @param amountOutMin The minimum amount of ETH to receive
     * @return The amount of ETH received
     */
    function _swapTokensForETH(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256) {
        IUniswapV2Router router = IUniswapV2Router(uniswapRouterAddress);
        
        // Create path
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = router.WETH();
        
        // Get initial ETH balance
        uint256 initialBalance = address(this).balance;
        
        emit DebugLog("Initial ETH balance", initialBalance);
        emit DebugLog("Token amount for swap", amountIn);
        
        // Approve router to spend tokens
        IERC20(tokenIn).approve(uniswapRouterAddress, amountIn);
        
        emit DebugLog("Tokens approved for router", amountIn);
        
        // Execute swap
        try router.swapExactTokensForETH(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 1800 // 30 minutes hardcoded deadline
        ) returns (uint[] memory /* amounts */) {
            // Calculate actual amount received
            uint256 finalBalance = address(this).balance;
            uint256 amountReceived = finalBalance - initialBalance;
            
            emit DebugLog("Final ETH balance", finalBalance);
            emit DebugLog("ETH received", amountReceived);
            
            require(amountReceived >= amountOutMin, "Insufficient ETH output");
            return amountReceived;
        } catch Error(string memory reason) {
            emit DebugLog("Swap failed with reason", 0);
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        } catch {
            emit DebugLog("Swap failed with unknown error", 0);
            revert("Swap failed with unknown error");
        }
    }
    
    /**
     * @dev Swap tokens for ETH with fee support
     * @param tokenIn The address of the token to swap
     * @param amountIn The amount of tokens to swap
     * @param amountOutMin The minimum amount of ETH to receive
     * @return The amount of ETH received
     */
    function _swapTokensForETHWithFees(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256) {
        IUniswapV2Router router = IUniswapV2Router(uniswapRouterAddress);
        
        // Create path
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = router.WETH();
        
        // Get initial ETH balance
        uint256 initialBalance = address(this).balance;
        
        emit DebugLog("Initial ETH balance (with fees)", initialBalance);
        emit DebugLog("Token amount for swap", amountIn);
        
        // Approve router to spend tokens
        IERC20(tokenIn).approve(uniswapRouterAddress, amountIn);
        
        emit DebugLog("Tokens approved for router (with fees)", amountIn);
        
        // Execute swap with fee support
        try router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 1800 // 30 minutes hardcoded deadline
        ) {
            // Calculate actual amount received
            uint256 finalBalance = address(this).balance;
            uint256 amountReceived = finalBalance - initialBalance;
            
            emit DebugLog("Final ETH balance", finalBalance);
            emit DebugLog("ETH received (with fees)", amountReceived);
            
            require(amountReceived >= amountOutMin, "Insufficient ETH output");
            return amountReceived;
        } catch Error(string memory reason) {
            emit DebugLog("Swap with fees failed with reason", 0);
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        } catch {
            emit DebugLog("Swap with fees failed with unknown error", 0);
            revert("Swap failed with unknown error");
        }
    }
    
    /**
     * @dev Swap tokens for tokens
     * @param tokenIn The address of the token to swap
     * @param tokenOut The address of the token to receive
     * @param amountIn The amount of tokens to swap
     * @param amountOutMin The minimum amount of tokens to receive
     * @return The amount of tokens received
     */
    function _swapTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256) {
        IUniswapV2Router router = IUniswapV2Router(uniswapRouterAddress);
        
        // Create path
        address[] memory path = new address[](3);
        path[0] = tokenIn;
        path[1] = router.WETH();
        path[2] = tokenOut;
        
        // Get initial balance to calculate exact amount received
        uint256 initialBalance = IERC20(tokenOut).balanceOf(address(this));
        
        emit DebugLog("Initial target token balance", initialBalance);
        emit DebugLog("Source token amount for swap", amountIn);
        
        // Approve router to spend tokens
        IERC20(tokenIn).approve(uniswapRouterAddress, amountIn);
        
        emit DebugLog("Tokens approved for router", amountIn);
        
        // Execute swap
        try router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 1800 // 30 minutes hardcoded deadline
        ) returns (uint[] memory /* amounts */) {
            // Calculate actual amount received
            uint256 finalBalance = IERC20(tokenOut).balanceOf(address(this));
            uint256 amountReceived = finalBalance - initialBalance;
            
            emit DebugLog("Final target token balance", finalBalance);
            emit DebugLog("Target tokens received", amountReceived);
            
            require(amountReceived >= amountOutMin, "Insufficient output amount");
            return amountReceived;
        } catch Error(string memory reason) {
            emit DebugLog("Swap failed with reason", 0);
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        } catch {
            emit DebugLog("Swap failed with unknown error", 0);
            revert("Swap failed with unknown error");
        }
    }
    
    /**
     * @dev Swap tokens for tokens with fee support
     * @param tokenIn The address of the token to swap
     * @param tokenOut The address of the token to receive
     * @param amountIn The amount of tokens to swap
     * @param amountOutMin The minimum amount of tokens to receive
     * @return The amount of tokens received
     */
    function _swapTokensForTokensWithFees(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256) {
        IUniswapV2Router router = IUniswapV2Router(uniswapRouterAddress);
        
        // Create path
        address[] memory path = new address[](3);
        path[0] = tokenIn;
        path[1] = router.WETH();
        path[2] = tokenOut;
        
        // Get initial balance to calculate exact amount received
        uint256 initialBalance = IERC20(tokenOut).balanceOf(address(this));
        
        emit DebugLog("Initial target token balance (with fees)", initialBalance);
        emit DebugLog("Source token amount for swap", amountIn);
        
        // Approve router to spend tokens
        IERC20(tokenIn).approve(uniswapRouterAddress, amountIn);
        
        emit DebugLog("Tokens approved for router (with fees)", amountIn);
        
        // Execute swap with fee support
        try router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 1800 // 30 minutes hardcoded deadline
        ) {
            // Calculate actual amount received
            uint256 finalBalance = IERC20(tokenOut).balanceOf(address(this));
            uint256 amountReceived = finalBalance - initialBalance;
            
            emit DebugLog("Final target token balance", finalBalance);
            emit DebugLog("Target tokens received (with fees)", amountReceived);
            
            require(amountReceived >= amountOutMin, "Insufficient output amount");
            return amountReceived;
        } catch Error(string memory reason) {
            emit DebugLog("Swap with fees failed with reason", 0);
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        } catch {
            emit DebugLog("Swap with fees failed with unknown error", 0);
            revert("Swap failed with unknown error");
        }
    }
    
    // View functions
    
    /**
     * @dev Get proposal details
     * @param proposalId The ID of the proposal
     * @return vaultId The ID of the vault
     * @return creator The address of the proposal creator
     * @return proposalType The type of the proposal
     * @return sourceToken The address of the source token
     * @return targetToken The address of the target token
     * @return amount The amount to trade
     * @return minAmountOut The minimum amount to receive
     * @return yesVotes The number of yes votes
     * @return noVotes The number of no votes
     * @return status The status of the proposal
     * @return hasFees Whether the token has transfer fees
     */
    function getProposalDetails(uint256 proposalId) 
        external 
        view 
        proposalExists(proposalId) 
        returns (
            uint256 vaultId,
            address creator,
            ProposalType proposalType,
            address sourceToken,
            address targetToken,
            uint256 amount,
            uint256 minAmountOut,
            uint256 yesVotes,
            uint256 noVotes,
            ProposalStatus status,
            bool hasFees
        ) 
    {
        TradeProposal storage proposal = tradeProposals[proposalId];
        
        return (
            proposal.vaultId,
            proposal.creator,
            proposal.proposalType,
            proposal.sourceToken,
            proposal.targetToken,
            proposal.amount,
            proposal.minAmountOut,
            proposal.yesVotes,
            proposal.noVotes,
            proposal.status,
            proposal.hasFees
        );
    }

    function getTimestampDetails(uint256 proposalId)
    external 
    view 
    proposalExists(proposalId)
    returns(
            uint256 vaultId,
            uint256 createdAt,
            uint256 executedAt
        )
    {
        TimeStamp storage time = timeStamp[proposalId];
        
        return (
            time.vaultId,
            time.createdAt,
            time.executedAt
        );
    }

    /**
     * @dev Get proposal retrieval details
     * @param proposalId The ID of the proposal
     * @return tokensRetrieved Whether tokens have been retrieved
     * @return amountReceived The amount received from the swap
     */
    function getProposalRetrievalDetails(uint256 proposalId)
        external
        view
        proposalExists(proposalId)
        returns (
            bool tokensRetrieved,
            uint256 amountReceived
        )
    {
        TradeProposal storage proposal = tradeProposals[proposalId];
        return (proposal.tokensRetrieved, proposal.amountReceived);
    }
    
    /**
     * @dev Check if a member has voted on a proposal
     * @param proposalId The ID of the proposal
     * @param member The address of the member
     * @return hasVoted Whether the member has voted
     * @return inFavor Whether the member voted in favor
     */
    function getMemberVote(uint256 proposalId, address member) 
        external 
        view 
        proposalExists(proposalId) 
        returns (bool hasVoted, bool inFavor) 
    {
        Vote storage vote = tradeProposals[proposalId].votes[member];
        return (vote.hasVoted, vote.inFavor);
    }
    
    /**
     * @dev Check if a proposal has enough votes to pass
     * @param proposalId The ID of the proposal
     * @return Whether the proposal has enough votes to pass
     */
    function hasEnoughVotes(uint256 proposalId) external view proposalExists(proposalId) returns (bool) {
        TradeProposal storage proposal = tradeProposals[proposalId];
        
        uint256 totalMembers = ICommunityVaultecCore(communityVaultecCoreAddress).getMemberCount(proposal.vaultId);
        uint256 requiredVotes = (totalMembers * VOTING_THRESHOLD) / 100;
        
        return proposal.yesVotes >= requiredVotes;
    }
    
    /**
     * @dev Get the number of votes required for a proposal to pass
     * @param proposalId The ID of the proposal
     * @return The number of votes required
     */
    function getRequiredVotes(uint256 proposalId) external view proposalExists(proposalId) returns (uint256) {
        TradeProposal storage proposal = tradeProposals[proposalId];
        
        uint256 totalMembers = ICommunityVaultecCore(communityVaultecCoreAddress).getMemberCount(proposal.vaultId);
        return (totalMembers * VOTING_THRESHOLD) / 100;
    }
    
    /**
     * @dev Check contract balances
     * @param token The token address (or ETH_ADDRESS for ETH)
     * @return The balance of the token in this contract
     */
    function checkContractBalance(address token) external view returns (uint256) {
        if (token == ETH_ADDRESS) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }
    
    /**
     * @dev Check if a token has transfer fees
     * @param token The address of the token
     * @return Whether the token has transfer fees
     */
    function checkTokenHasFees(address token) external view returns (bool) {
        return tokenHasFees[token];
    }
    
    // Fallback and receive functions to accept ETH
    receive() external payable {}
    fallback() external payable {}
}
