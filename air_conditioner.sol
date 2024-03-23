// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;



import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";



contract Air_Conditioner is ERC20, ReentrancyGuard {



    // Events for logging various actions on the contract
    event Bought    (address indexed buyer, uint256 ethAmount, uint256 airAmount);
    event Sold      (address indexed seller, uint256 airAmount, uint256 ethAmount);
    event Staked    (address indexed user, uint256 amount);
    event Unstaked  (address indexed user, uint256 amount);
    event Withdrawn (address indexed user, uint256 amount);
    event Claimed   (address indexed user, uint256 amount);
    event crossChainReceive  (uint256 chainID, address indexed to, uint256 amount);
    event CrossChainRequested(address indexed user, uint256 amount, uint256 chainId);



    // State variables
    address private owner;
    address private relayer;



    // Structs for managing different functionalities
    struct Stake              { uint256 amount; uint256 startTime;     }
    struct Pending            { uint256 amount; uint256 releaseTime;   }
    struct Referral           { address fd1; address fd2; address fd3; }
    struct CrossChainTransfer { uint256 amount; uint256 chainId;       }



    // Mappings for different contract states
    mapping(address => bool)               public check_airdropClaimed;
    mapping(address => Stake)              public check_stakingAmount;
    mapping(address => Pending)            public check_pendingWithdrawal;
    mapping(address => Referral)           public check_referrals;
    mapping(address => CrossChainTransfer) public crossChainTransfers;



    /**
     * @dev Constructor to mint initial tokens.
     * Sets the contract deployer as the initial owner and relayer.
     * Mints a specified amount of tokens to the deployer.
     */
    constructor() ERC20("AIR", "AIR") {
        owner   = _msgSender(); // Set the contract deployer as the initial owner
        relayer = _msgSender(); // Set the contract deployer as the initial relayer
        _mint(_msgSender(), 1000000000 * 10 ** decimals()); // Mint initial token supply to the deployer
    }



    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public {
        require(_msgSender() == owner, "Only owner can transfer ownership");
        require(newOwner != address(0), "New owner cannot be the zero address");
        owner = newOwner; // Transfer ownership to the new owner
    }



    /**
     * @dev Sets the relayer address.
     * Can only be called by the contract owner.
     */
    function setRelayer(address _relayer) public {
        require(_msgSender() == owner, "Only owner can set relayer");
        relayer = _relayer; // Set the new relayer
    }



    /**
     * @dev Allows the relayer to mint tokens on a specific chain.
     * Can only be called by the relayer.
     *
     * Emits a {CrossChainReceive} event.
     */
    function relayerMint(uint256 chainID, address to, uint256 amount) public {
        require(_msgSender() == relayer, "Only relayer can mint tokens");
        _mint(to, amount); // Mint tokens to the specified address
        emit crossChainReceive(chainID, to, amount); // Emit an event for cross-chain receive
    }



    /**
     * @dev Allows users to request a cross-chain transfer of their tokens.
     * Burns the user's tokens and records the cross-chain transfer request.
     *
     * Emits a {CrossChainRequested} event.
     */
    function requestCrossChainTransfer(uint256 amount, uint256 chainId) public {
        require(balanceOf(_msgSender()) >= amount, "Insufficient balance");
        _burn(_msgSender(), amount); // Burn the specified amount of tokens
        crossChainTransfers[_msgSender()] = CrossChainTransfer(amount, chainId); // Record the cross-chain transfer request
        emit CrossChainRequested(_msgSender(), amount, chainId); // Emit an event for the cross-chain request
    }



    /**
     * @dev Calculates the amount of AIR tokens that can be purchased with a given amount of ETH.
     * This calculation is based on the current total supply of AIR tokens and applies a conversion
     * rate that scales linearly with the supply.
     *
     * @param ethAmount The amount of Ether (in wei) to convert into AIR tokens.
     * @return amount The calculated amount of AIR tokens that can be purchased.
     */
    function check_purchaseAmount(uint256 ethAmount) public view returns (uint256) {
        require(ethAmount < 99 ether, "Each transaction amount cannot exceed 99 native coinbase.");
        uint256 ts = totalSupply();
        uint256 dec = decimals();
        uint256 amount;
        assembly {
            // Convert ethAmount to wei for precision in calculations
            let ethAmountInWei := mul(ethAmount, exp(10, 18))

            // Calculate the purchase amount using a linear conversion formula
            // to avoid precision loss: (EthAmountInWei * TotalSupply) / (10^(18 + decimals))
            amount := div(mul(ethAmountInWei, ts), exp(10, add(18, dec)))
        }
        return amount;
    }



    /**
     * @dev Allows a user to refer a new friend. Each user can refer up to three friends.
     * This function updates the referral data for both the referrer and the referred friend.
     * 
     * Requirements:
     * - `newFriend` cannot be the zero address.
     * - `newFriend` cannot be the same as the referrer (msg.sender).
     * - A user cannot refer the same address more than once.
     * - Each user can refer a maximum of three friends.
     *
     * @param newFriend The address of the friend being referred.
     */
    function refer(address newFriend) external {
        require(newFriend != address(0), "Invalid address");
        require(newFriend != _msgSender(), "Cannot refer yourself");
        Referral storage userReferral = check_referrals[_msgSender()];
        Referral storage friendReferral = check_referrals[newFriend];
        // Ensure the address is not already referred by the user
        require(
            userReferral.fd1 != newFriend &&
            userReferral.fd2 != newFriend &&
            userReferral.fd3 != newFriend,
            "Address already referred"
        );
        // Add the new friend to the user's referral list
        if (userReferral.fd1 == address(0)) {
            userReferral.fd1 = newFriend;
        } else if (userReferral.fd2 == address(0)) {
            userReferral.fd2 = newFriend;
        } else if (userReferral.fd3 == address(0)) {
            userReferral.fd3 = newFriend;
        } else {
            revert("Your referral limit is full");
        }
        // Add the user as a referrer in the friend's referral data
        if (friendReferral.fd1 == address(0)) {
            friendReferral.fd1 = _msgSender();
        } else if (friendReferral.fd2 == address(0)) {
            friendReferral.fd2 = _msgSender();
        } else if (friendReferral.fd3 == address(0)) {
            friendReferral.fd3 = _msgSender();
        } else {
            revert("Friend's referral limit is full");
        }
    }



    /**
    * @dev Executes a token purchase operation.
    * 
    * This function handles the internal logic for purchasing AIR tokens in exchange for ETH.
    * It calculates the number of AIR tokens to be purchased based on the provided ETH amount,
    * transfers these tokens to the buyer, and transfers the ETH to the contract owner.
    *
    * Emits a `Bought` event upon successful purchase.
    *
    * Requirements:
    * - The call to transfer AIR tokens to the buyer must succeed.
    * - ETH amount sent must be transferred to the contract owner.
    */
    function buy() internal nonReentrant {
        // Calculate the amount of AIR tokens that can be bought with the provided ETH amount.
        uint256 amount = check_purchaseAmount(msg.value);
        // Construct calldata for transferring AIR tokens to the buyer.
        bytes memory transferCalldata = abi.encodeWithSelector(ERC20(address(this)).transfer.selector, _msgSender(), amount);
        // Call the ERC20 transfer function to transfer tokens to the buyer.
        (bool successTransfer, ) = address(this).call(transferCalldata);
        require(successTransfer, "Token transfer failed");
        // Transfer the ETH amount to the contract owner.
        uint256 ethAmount = msg.value;
        address ownerAddress = owner;
        assembly {
            // Call to transfer ETH to the owner.
            let success := call(gas(), ownerAddress, ethAmount, 0, 0, 0, 0)

            // Revert the transaction if the ETH transfer fails.
            if iszero(success) { revert(0, 0) }
        }

        // Emit an event logging the purchase.
        emit Bought(_msgSender(), msg.value, amount);
    }



    /**
     * @dev Claims the airdrop for the sender. Can only be claimed once per address.
     * This function mints a predefined amount of tokens to the sender's address.
     * Requires that the airdrop for the sender has not already been claimed.
     */
    function claim() external nonReentrant {
        require(!check_airdropClaimed[_msgSender()], "Airdrop already claimed.");
        _mint(_msgSender(), 1 * 10 ** decimals());
        check_airdropClaimed[_msgSender()] = true;
        emit Claimed(_msgSender(), 1 * 10 ** decimals());
    }



    /**
     * @dev Stakes a specified amount of tokens by the sender. The tokens are burned
     * from the sender's account and recorded in the staking balance.
     * Requires that the amount to be staked is greater than 0.
     *
     * @param _amount The amount of tokens to be staked.
     */
    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");
        uint256 check_stakingAmountSlot;
        assembly {
            check_stakingAmountSlot := check_stakingAmount.slot
        }
        _burn(_msgSender(), _amount);
        check_stakingAmount[_msgSender()].amount += _amount;
        check_stakingAmount[_msgSender()].startTime = block.timestamp;
        emit Staked(_msgSender(), _amount);
    }



    /**
     * @dev Checks if a given user address currently has tokens staked.
     *
     * @param user The address of the user to check staking status for.
     * @return A boolean value indicating if the user has tokens staked.
     */
    function isStaking(address user) public view returns (bool) {
        return check_stakingAmount[user].amount > 0;
    }



    /**
    * @dev Calculates the Annual Percentage Yield (APY) for a given user.
    * The base APY is 10%, and additional 10% is added for each referred friend who is staking.
    * This function uses inline assembly for efficient storage access and computation.
    * 
    * @param user The address of the user for whom to calculate the APY.
    * @return The total APY for the user, including bonuses from staking referrals.
    */
    function check_APY(address user) public view returns (uint256) {
        uint256 baseAPY = 10; // 基础APY为10%
        uint256 bonusAPY;
        assembly {
            // Load referred friend addresses
            let fd1 := sload(add(check_referrals.slot, mul(user, 4)))
            let fd2 := sload(add(check_referrals.slot, add(mul(user, 4), 1)))
            let fd3 := sload(add(check_referrals.slot, add(mul(user, 4), 2)))
            // Calculate the additional APY for each staking friend
            // Adds 10% for each friend who is currently staking
            if gt(sload(add(check_stakingAmount.slot, mul(fd1, 2))), 0) {
                bonusAPY := add(bonusAPY, 10)
            }
            if gt(sload(add(check_stakingAmount.slot, mul(fd2, 2))), 0) {
                bonusAPY := add(bonusAPY, 10)
            }
            if gt(sload(add(check_stakingAmount.slot, mul(fd3, 2))), 0) {
                bonusAPY := add(bonusAPY, 10)
            }
        }
        return baseAPY + bonusAPY;
    }



    /**
     * @dev Calculates the total balance of a user's staked tokens including earned interest.
     * @param user The address of the user whose staking balance is being checked.
     * @return The total amount of staked tokens including interest for the given user.
     */
    function check_stakingBalance(address user) public view returns (uint256) {
        Stake memory userStake = check_stakingAmount[user];
        // If the user hasn't staked any tokens, return 0
        if (userStake.amount == 0) return 0;
        // Calculate the annual percentage yield (APY) for the user
        uint256 totalAPY = check_APY(user);
        // Calculate the time the tokens have been staked
        uint256 stakedTime = block.timestamp - userStake.startTime;
        // Calculate the interest earned on staked tokens
        uint256 stakingInterest = userStake.amount * totalAPY / 100 * stakedTime / 365 days;
        // Return the total staked amount including earned interest
        return userStake.amount + stakingInterest;
    }



    /**
     * @dev Unstakes the tokens of the caller and records the total amount including interest.
     * The unstaked tokens are set to be withdrawable after a fixed period.
     */
    function unstake() external nonReentrant {
        uint256 stakedAmount = check_stakingAmount[_msgSender()].amount;
        // Ensure the user has tokens staked before unstaking
        require(stakedAmount > 0, "No staked amount");
        // Calculate the total amount that can be withdrawn, including interest
        uint256 totalAmount = check_stakingBalance(_msgSender());
        // Reset the user's staked amount and start time
        check_stakingAmount[_msgSender()] = Stake({amount: 0, startTime: 0});
        // Set up the withdrawal with the total amount and a 30-day delay
        check_pendingWithdrawal[_msgSender()] = Pending({
            amount: totalAmount,
            releaseTime: block.timestamp + 30 days
        });
        // Emit an event for unstaking action
        emit Unstaked(_msgSender(), stakedAmount);
    }



    /**
     * @dev Allows users to withdraw their staked tokens after the lock period.
     * Requirements:
     * - The current timestamp must be greater than or equal to the release time.
     * - The user must have a pending withdrawal.
     */
    function withdraw() external nonReentrant {
        Pending storage withdrawal = check_pendingWithdrawal[_msgSender()];
        require(block.timestamp >= withdrawal.releaseTime, "Cannot withdraw yet");
        require(withdrawal.amount > 0, "No pending withdrawal");

        uint256 amountToWithdraw = withdrawal.amount;
        delete check_pendingWithdrawal[_msgSender()]; // Clear the pending withdrawal record.
        _mint(_msgSender(), amountToWithdraw); // Mint the tokens back to the user's address.

        emit Withdrawn(_msgSender(), amountToWithdraw); // Emit an event for the withdrawal.
    }



    /**
     * @dev Fallback function to handle ETH sent directly to the contract.
     * Calls the buy function when ETH is received.
     */
    fallback() external payable nonReentrant {
        buy();
    }



    /**
     * @dev Receive function to handle ETH sent directly to the contract.
     * It's an alias to the fallback function.
     */
    receive() external payable nonReentrant {
        buy();
    }

}
