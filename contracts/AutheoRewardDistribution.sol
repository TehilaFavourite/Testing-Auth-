// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract AutheoRewardDistribution is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Token configuration
    IERC20 public immutable Autheo;
    uint256 public immutable totalSupply;

    // Constants for decimal handling
    uint256 private constant SCALE = 1e18;

    // Allocation percentages (scaled by DECIMALS)
    uint256 public constant BUG_BOUNTY_ALLOCATION_PERCENTAGE = 6000; // 60%  of total supply
    uint256 public constant DAPP_REWARD_ALLOCATION_PERCENTAGE = 400; // 4%  of total supply
    uint256 public constant DEVELOPER_REWARD_ALLOCATION_PERCENTAGE = 200; // 2%  of total supply
    uint256 private constant MAX_BPS = 10000;

    // Fixed reward amounts
    uint256 public immutable MONTHLY_DAPP_REWARD = 5000 * SCALE;
    uint256 public immutable MONTHLY_UPTIME_BONUS = 500 * SCALE; // more than three smart contract deployed and more than fitfteen txs
    uint256 public immutable DEVELOPER_DEPLOYMENT_REWARD = 1500 * SCALE; // monthly reward

    // TGE status
    bool public isTestnet;

    // Claim amounts
    uint256 public claimPerContractDeployer;
    uint256 public claimPerDappUser;

    // Tracking variables
    uint256 public totalDappRewardsIds;
    uint256 public totalDappRewardsClaimed;
    uint256 public totalContractDeploymentClaimed;

    // Bug bounty reward calculations
    uint256 public lowRewardPerUser;
    uint256 public mediumRewardPerUser;
    uint256 public highRewardPerUser;

    uint256 public totalBugBountyRewardsClaimed;
    uint256 public totalLowBugBountyUserNumber;
    uint256 public totalMediumBugBountyUserNumber;
    uint256 public totalHighBugBountyUserNumber;
    // Constants for reward percentages
    uint256 public constant LOW_PERCENTAGE = 500;
    uint256 public constant MEDIUM_PERCENTAGE = 3500;
    uint256 public constant HIGH_PERCENTAGE = 6000;

    // User registration arrays
    address[] public lowBugBountyUsers;
    address[] public mediumBugBountyUsers;
    address[] public highBugBountyUsers;
    address[] public whitelistedContractDeploymentUsers;
    address[] public whitelistedDappRewardUsers;

    address[] public allUsers;

    uint256 public dappUserCurrentId;
    uint256 public contractDeployerCurrentId;
    uint256 public lowBugBountyCurrentId;
    uint256 public mediumBugBountyCurrentId;
    uint256 public highBugBountyCurrentId;

    // Mapping to track bug bounty criticality for users
    mapping(address => mapping(uint256 => bool))
        public isWhitelistedContractDeploymentUsersForId;
    mapping(address => mapping(uint256 => bool))
        public isWhitelistedDappUsersForId;

    mapping(address => bool) public isContractDeploymentUsersClaimed;
    mapping(address => bool) public isWhitelistedDappUsers;
    mapping(address => bool) public isDappUsersClaimed;
    mapping(address => bool) public isBugBountyUsersClaimed;
    mapping(address => bool) public hasGoodUptime;
    mapping(address => mapping(uint256 => BugCriticality))
        public bugBountyCriticality;

    mapping(address => bool) public hasReward;
    mapping(address => bool) public iswhitelistedContractDeploymentUsers;
    mapping(address => bool) public iswhitelistedDappRewardUsers;

    mapping(address => uint256) public lastContractDeploymentClaim;
    mapping(address => uint256) public contractDeploymentRegistrationTime;
    // Mapping to track authorized addresses
    mapping(address => bool) public isAuthorized;

    // Bug Criticality Enum
    enum BugCriticality {
        NONE,
        LOW,
        MEDIUM,
        HIGH
    }

    // Events
    event WhitelistUpdated(
        string indexed claimType,
        address indexed user,
        uint256 indexed id
    );
    event Claimed(
        string indexed claimType,
        address indexed user,
        uint256 indexed amount
    );
    event ClaimAmountUpdated(uint256 indexed newClaimedAmount);
    event EmergencyWithdraw(address indexed token, uint256 indexed amount);
    event TestnetStatusUpdated(bool indexed status);
    event Received(address indexed sender, uint256 indexed amount);
    event Withdrawal(address indexed user, uint256 indexed amount);

    error USER_HAS_NO_CLAIM(address user);
    error INSUFFICIENT_BALANCE();

    // Modifiers
    modifier whenTestnetInactive() {
        require(!isTestnet, "Contract is in testnet mode");
        _;
    }

    modifier onlyAuthorized() {
        require(isAuthorized[msg.sender], "Unauthorized");
        _;
    }

    constructor(address _autheoToken) Ownable(msg.sender) {
        require(_autheoToken != address(0), "Invalid token address");
        Autheo = IERC20(_autheoToken);
        totalSupply = 10500000000000000000000000;
        totalDappRewardsIds = 0;
        totalLowBugBountyUserNumber = 0;
        totalMediumBugBountyUserNumber = 0;
        totalHighBugBountyUserNumber = 0;
        dappUserCurrentId = 0;
        contractDeployerCurrentId = 0;
        lowBugBountyCurrentId = 0;
        mediumBugBountyCurrentId = 0;
        highBugBountyCurrentId = 0;
        isTestnet = true;
        isAuthorized[msg.sender] = true;
    }

    function setAuthorized(address _address, bool _status) external onlyOwner {
        isAuthorized[_address] = _status;
    }

    function setTestnetStatus(bool _status) external onlyOwner {
        isTestnet = _status;
        emit TestnetStatusUpdated(_status);
    }

    function transferNativeToken(
        address payable recipient,
        uint256 amount
    ) private {
        if (address(this).balance < amount) revert INSUFFICIENT_BALANCE();
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
    }

    function setClaimPerContractDeployer(
        uint256 _claimAmount
    ) external onlyOwner {
        claimPerContractDeployer = _claimAmount;
        emit ClaimAmountUpdated(_claimAmount);
    }

    function setClaimPerDappUser(uint256 _claimAmount) external onlyOwner {
        claimPerDappUser = _claimAmount;
        emit ClaimAmountUpdated(_claimAmount);
    }

    function registerLowBugBountyUsers(
        address[] calldata _lowBugBountyUsers
    ) external onlyOwner {
        require(isTestnet, "Registration period has ended");
        lowBugBountyCurrentId++;
        _registerBugBountyUsers(
            _lowBugBountyUsers,
            lowBugBountyCurrentId,
            BugCriticality.LOW,
            "Low Bug Bounty"
        );
    }

    function registerMediumBugBountyUsers(
        address[] calldata _mediumBugBountyUsers
    ) external onlyOwner {
        require(isTestnet, "Registration period has ended");
        mediumBugBountyCurrentId++;
        _registerBugBountyUsers(
            _mediumBugBountyUsers,
            mediumBugBountyCurrentId,
            BugCriticality.MEDIUM,
            "Medium Bug Bounty"
        );
    }

    function registerHighBugBountyUsers(
        address[] calldata _highBugBountyUsers
    ) external onlyOwner {
        require(isTestnet, "Registration period has ended");
        highBugBountyCurrentId++;
        _registerBugBountyUsers(
            _highBugBountyUsers,
            highBugBountyCurrentId,
            BugCriticality.HIGH,
            "High Bug Bounty"
        );
    }

    function _registerBugBountyUsers(
        address[] calldata _users,
        uint256 currentId,
        BugCriticality criticality,
        string memory claimType
    ) private {
        for (uint256 i = 0; i < _users.length; i++) {
            address user = _users[i];
            if (
                user == address(0) ||
                bugBountyCriticality[user][currentId] != BugCriticality.NONE
            ) continue;

            if (criticality == BugCriticality.LOW)
                totalLowBugBountyUserNumber++;
            else if (criticality == BugCriticality.MEDIUM)
                totalMediumBugBountyUserNumber++;
            else if (criticality == BugCriticality.HIGH)
                totalHighBugBountyUserNumber++;

            if (!hasReward[user]) allUsers.push(user);
            bugBountyCriticality[user][currentId] = criticality;
            hasReward[user] = true;
            emit WhitelistUpdated(claimType, user, currentId);
        }
    }

    function registerContractDeploymentUsers(
        address[] calldata _contractDeploymentUsers
    ) external onlyOwner {
        require(isTestnet, "Registration period has ended");
        require(_contractDeploymentUsers.length > 0, "Empty array");
        contractDeployerCurrentId++;
        for (uint256 i = 0; i < _contractDeploymentUsers.length; i++) {
            address user = _contractDeploymentUsers[i];
            if (
                user == address(0) ||
                isWhitelistedContractDeploymentUsersForId[user][
                    contractDeployerCurrentId
                ]
            ) continue;

            isWhitelistedContractDeploymentUsersForId[user][
                contractDeployerCurrentId
            ] = true;
            if (!iswhitelistedContractDeploymentUsers[user]) {
                whitelistedContractDeploymentUsers.push(user);
                iswhitelistedContractDeploymentUsers[user] = true;
            }
            if (!hasReward[user]) {
                allUsers.push(user);
                hasReward[user] = true;
            }
            emit WhitelistUpdated(
                "Contract Deployment",
                user,
                contractDeployerCurrentId
            );
        }
    }

    function registerDappUsers(
        address[] calldata _dappRewardsUsers,
        bool[] calldata _userUptime
    ) external onlyOwner {
        require(isTestnet, "Registration period has ended");
        require(
            _dappRewardsUsers.length == _userUptime.length &&
                _dappRewardsUsers.length > 0,
            "Invalid input"
        );
        dappUserCurrentId++;
        for (uint256 i = 0; i < _dappRewardsUsers.length; i++) {
            address user = _dappRewardsUsers[i];
            if (
                user == address(0) ||
                isWhitelistedDappUsersForId[user][dappUserCurrentId]
            ) continue;

            if (_userUptime[i]) hasGoodUptime[user] = true;
            isWhitelistedDappUsersForId[user][dappUserCurrentId] = true;
            if (!iswhitelistedDappRewardUsers[user]) {
                whitelistedDappRewardUsers.push(user);
                iswhitelistedDappRewardUsers[user] = true;
            }
            if (!hasReward[user]) {
                allUsers.push(user);
                hasReward[user] = true;
            }
            emit WhitelistUpdated("Dapp Users", user, dappUserCurrentId);
        }
    }

    /**
     * @dev Claim rewards for whitelisted address - Only accessible when testnet is inactive
     */
    function claimReward(
        bool _contractDeploymentClaim,
        bool _dappUserClaim,
        bool _bugBountyClaim
    ) external nonReentrant whenNotPaused whenTestnetInactive onlyAuthorized {
        if (_contractDeploymentClaim) __contractDeploymentClaim(msg.sender);
        else if (_dappUserClaim) __claimDappRewards(msg.sender);
        else if (_bugBountyClaim) __bugBountyClaim(msg.sender);
        else revert USER_HAS_NO_CLAIM(msg.sender);
    }

    function __bugBountyClaim(address _user) private {
        require(!isBugBountyUsersClaimed[_user], "Already claimed");
        require(
            totalLowBugBountyUserNumber > 0 &&
                totalMediumBugBountyUserNumber > 0 &&
                totalHighBugBountyUserNumber > 0,
            "No users registered"
        );

        uint256 totalBugBountyAllocation = (totalSupply *
            BUG_BOUNTY_ALLOCATION_PERCENTAGE) / MAX_BPS;
        lowRewardPerUser = totalLowBugBountyUserNumber > 0
            ? ((totalBugBountyAllocation * LOW_PERCENTAGE) / 10000) /
                totalLowBugBountyUserNumber
            : 0;
        mediumRewardPerUser = totalMediumBugBountyUserNumber > 0
            ? ((totalBugBountyAllocation * MEDIUM_PERCENTAGE) / 10000) /
                totalMediumBugBountyUserNumber
            : 0;
        highRewardPerUser = totalHighBugBountyUserNumber > 0
            ? ((totalBugBountyAllocation * HIGH_PERCENTAGE) / 10000) /
                totalHighBugBountyUserNumber
            : 0;

        uint256 numOfRegistering = max(
            max(lowBugBountyCurrentId, mediumBugBountyCurrentId),
            highBugBountyCurrentId
        );
        uint256 totalRewardAmount;
        for (uint256 i = 1; i <= numOfRegistering; i++) {
            if (bugBountyCriticality[_user][i] == BugCriticality.LOW)
                totalRewardAmount += lowRewardPerUser;
            else if (bugBountyCriticality[_user][i] == BugCriticality.MEDIUM)
                totalRewardAmount += mediumRewardPerUser;
            else if (bugBountyCriticality[_user][i] == BugCriticality.HIGH)
                totalRewardAmount += highRewardPerUser;
        }

        isBugBountyUsersClaimed[_user] = true;
        totalBugBountyRewardsClaimed += totalRewardAmount;
        require(
            totalBugBountyRewardsClaimed <= totalBugBountyAllocation,
            "Exceeds allocation"
        );
        transferNativeToken(payable(_user), totalRewardAmount);
        emit Claimed("Bug Bounty", _user, totalRewardAmount);
    }

    function __contractDeploymentClaim(address _user) private {
        uint256 actingMonths = getCurrentDeploymentMultiplier(_user);
        require(actingMonths > 0, "User not eligible");
        require(!isContractDeploymentUsersClaimed[_user], "Already claimed");

        uint256 totalReward = DEVELOPER_DEPLOYMENT_REWARD * actingMonths;
        isContractDeploymentUsersClaimed[_user] = true;
        totalContractDeploymentClaimed += totalReward;
        require(
            totalContractDeploymentClaimed <=
                (totalSupply * DEVELOPER_REWARD_ALLOCATION_PERCENTAGE) /
                    MAX_BPS,
            "Exceeds allocation"
        );
        transferNativeToken(payable(_user), totalReward);
        emit Claimed(
            string.concat(
                "Contract Deployment Reward - ",
                Strings.toString(actingMonths),
                " months"
            ),
            _user,
            totalReward
        );
    }

    function __claimDappRewards(address _user) private {
        uint256 actingMonths;
        for (uint256 i = 1; i <= dappUserCurrentId; i++) {
            if (isWhitelistedDappUsersForId[_user][i]) actingMonths++;
        }
        require(actingMonths > 0, "User not eligible");
        require(!isDappUsersClaimed[_user], "Already claimed");

        uint256 rewardAmount = MONTHLY_DAPP_REWARD * actingMonths;
        if (hasGoodUptime[_user]) rewardAmount += MONTHLY_UPTIME_BONUS;
        isDappUsersClaimed[_user] = true;
        totalDappRewardsClaimed += rewardAmount;
        require(
            totalDappRewardsClaimed <=
                (totalSupply * DAPP_REWARD_ALLOCATION_PERCENTAGE) / MAX_BPS,
            "Exceeds allocation"
        );
        transferNativeToken(payable(_user), rewardAmount);
        emit Claimed(
            string.concat(
                "Dapp User Reward - ",
                Strings.toString(actingMonths),
                " months"
            ),
            _user,
            rewardAmount
        );
    }

    /**
     * @dev Calculate remaining bug bounty rewards for each criticality level
     */
    function calculateRemainingClaimedAmount() external view returns (uint256) {
        return (totalBugBountyRewardsClaimed +
            totalContractDeploymentClaimed +
            totalDappRewardsClaimed);
    }

    /**
     * @dev Retrieve all whitelisted contract deployment users
     * @return address[] Array of whitelisted addresses
     */
    function getWhitelistedContractDeploymentUsers()
        external
        view
        returns (address[] memory)
    {
        return whitelistedContractDeploymentUsers;
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // Fallback function is called when msg.data is not empty
    fallback() external payable {
        emit Received(msg.sender, msg.value);
    }

    // Function to withdraw Ether from this contract
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert INSUFFICIENT_BALANCE();
        payable(owner()).transfer(balance);
        emit Withdrawal(owner(), balance);
    }

    // Function to get the balance of this contract
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Calculate remaining contract deployment rewards allocation
     * @notice Returns the amount of tokens still available for contract deployment rewards
     * @return uint256 The remaining amount of tokens available for contract deployment distribution
     */
    function calculateRemainingContractDeploymentReward()
        external
        view
        returns (uint256)
    {
        uint256 totalDeploymentAllocation = (totalSupply *
            DEVELOPER_REWARD_ALLOCATION_PERCENTAGE) / MAX_BPS;
        return
            totalContractDeploymentClaimed >= totalDeploymentAllocation
                ? 0
                : totalDeploymentAllocation - totalContractDeploymentClaimed;
    }

    /**
     * @dev Retrieve all whitelisted dApp reward users
     * @return address[] Array of whitelisted addresses
     */
    function getWhitelistedDappRewardUsers()
        external
        view
        returns (address[] memory)
    {
        return whitelistedDappRewardUsers;
    }

    /**
     * @dev Emergency withdraw any accidentally sent tokens
     * @param token Address of token to withdraw
     */
    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");

        IERC20(token).safeTransfer(owner(), balance);
        emit EmergencyWithdraw(token, balance);
    }

    /**
     * @dev Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Calculate remaining dApp rewards allocation
     */
    function calculateRemainingDappRewards() external view returns (uint256) {
        uint256 totalDappAllocation = (totalSupply *
            DAPP_REWARD_ALLOCATION_PERCENTAGE) / MAX_BPS;
        return
            totalDappRewardsClaimed >= totalDappAllocation
                ? 0
                : totalDappAllocation - totalDappRewardsClaimed;
    }

    function getAllUsers() external view returns (address[] memory) {
        return allUsers;
    }

    function getCurrentDeploymentMultiplier(
        address _user
    ) public view returns (uint256) {
        uint256 actingMonths;
        for (uint256 i = 1; i <= contractDeployerCurrentId; i++) {
            if (isWhitelistedContractDeploymentUsersForId[_user][i])
                actingMonths++;
        }
        return actingMonths;
    }

    function max(uint256 a, uint256 b) private pure returns (uint256) {
        return a >= b ? a : b;
    }
}
