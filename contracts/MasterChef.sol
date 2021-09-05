// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';

import "./FuniToken.sol";
import "./Staking.sol";

// import "@nomiclabs/buidler/console.sol";

// MasterChef is the master of Funi. He can make Funi and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once FUNI is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    
    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of FUNIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accFuniPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accFuniPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    
    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. FUNIs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that CAKEs distribution occurs.
        uint256 accFuniPerShare; // Accumulated FUNIs per share, times 1e12. See below.
    }
    
    // The FUNI TOKEN!
    FuniToken public funiToken;
    Staking public staking;
    
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when FUNI mining starts.
    uint256 public startBlock;
    
    // The percentage of FUNI token rewards distributed to FUNI pool
    uint256 public funiPoolPercent = 50;
    
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    
    modifier validatePoolByPid(uint256 _pid) {
        require (_pid < poolInfo.length, "Pool does not exist") ;
        _;
    }
    
    constructor(
        FuniToken _funiToken,
        Staking _staking,
        uint256 _startBlock
    ) public {
        funiToken = _funiToken;
        staking = _staking;
        startBlock = _startBlock;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _funiToken,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accFuniPerShare: 0
        }));

        totalAllocPoint = 1000;

    }
    
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }
    
    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accFuniPerShare: 0
        }));
        updateStakingPool();
    }
    
    // Update the given pool's FUNI allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if(_pid == 0){
            return;
        }
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            updateStakingPool();
        }
    }
    
    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            uint denominator = 100 - funiPoolPercent;
            uint funiPoints = funiPoolPercent.mul(points).div(denominator);
            poolInfo[0].allocPoint = funiPoints;
            totalAllocPoint = funiPoints + points;
        }
    }
    
    // View function to see pending alitas on frontend.
    function pendingFuni(uint256 _pid, address _user) external view validatePoolByPid(_pid) returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accFuniPerShare = pool.accFuniPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 funiReward = getClaimableReward(pool.lastRewardBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accFuniPerShare = accFuniPerShare.add(funiReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accFuniPerShare).div(1e12).sub(user.rewardDebt);
    }
    
    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }
    
    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 funiReward = getClaimableReward(pool.lastRewardBlock).mul(pool.allocPoint).div(totalAllocPoint);
        funiToken.mint(address(staking), funiReward);
        pool.accFuniPerShare = pool.accFuniPerShare.add(funiReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }
    
    // Deposit LP tokens to MasterChef for FUNI allocation.
    function deposit(uint256 _pid, uint256 _amount) public {

        require (_pid != 0, 'deposit FUNI by staking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accFuniPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accFuniPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }
    
    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {

        require (_pid != 0, 'withdraw FUNI by unstaking');
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accFuniPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accFuniPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }
    
    // Stake FUNI tokens to MasterChef
    function enterStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accFuniPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accFuniPerShare).div(1e12);

        emit Deposit(msg.sender, 0, _amount);
    }
    
    // Withdraw FUNI tokens from STAKING.
    function leaveStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accFuniPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accFuniPerShare).div(1e12);

        emit Withdraw(msg.sender, 0, _amount);
    }
    
    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }
    
    // Safe funiToken transfer function, just in case if rounding error causes pool to not have enough FUNIs.
    function safeTransfer(address _to, uint256 _amount) internal {
        staking.safeTransfer(_to, _amount);
    }
    
    /**
     * @dev Returns the result of (base ** exponent) with SafeMath
     * @param base The base number. Example: 2
     * @param exponent The exponent used to raise the base. Example: 3
     * @return A number representing the given base taken to the power of the given exponent. Example: 2 ** 3 = 8
     */
    function pow(uint base, uint exponent) internal pure returns (uint) {
        if (exponent == 0) {
            return 1;
        } else if (exponent == 1) {
            return base;
        } else if (base == 0 && exponent != 0) {
            return 0;
        } else {
            uint result = base;
            for (uint i = 1; i < exponent; i++) {
                result = result.mul(base);
            }
            return result;
        }
    }
    
    /**
     * @dev Caculate the reward per block at the period: (keepPercent / 100) ** period * initialRewardPerBlock
     * @param periodIndex The period index. The period index must be between [0, maximumPeriodIndex]
     * @return A number representing the reward token per block at specific period. Result is scaled by 1e18.
     */
    function getRewardPerBlock(uint periodIndex) public view returns (uint) {
        if(periodIndex > funiToken.getMaximumPeriodIndex()){
            return 0;
        }
        else{
            return pow(funiToken.getKeepPercent(), periodIndex).mul(funiToken.getInitialRewardPerBlock()).div(pow(100, periodIndex));
        }
    }
    
    /**
     * @dev Calculate the block number corresponding to each milestone at the beginning of each period.
     * @param periodIndex The period index. The period index must be between [0, maximumPeriodIndex]
     * @return A number representing the block number of the milestone at the beginning of the period.
     */
    function getBlockNumberOfMilestone(uint periodIndex) public view returns (uint) {
        return funiToken.getBlockPerPeriod().mul(periodIndex).add(startBlock);
    }
    
    /**
     * @dev Determine the period corresponding to any block number.
     * @param blockNumber The block number. The block number must be >= startBlock
     * @return A number representing period index of the input block number.
     */
    function getPeriodIndexByBlockNumber(uint blockNumber) public view returns (uint) {
        require(blockNumber >= startBlock, 'MasterChef: blockNumber must be greater or equal startBlock');
        return blockNumber.sub(startBlock).div(funiToken.getBlockPerPeriod());
    }
    
    /**
     * @dev Calculate the reward that can be claimed from the last received time to the present time.
     * @param lastRewardBlock The block number of the last received time 
     * @return A number representing the reclamable FUNI tokens. Result is scaled by 1e18.
     */
    function getClaimableReward(uint lastRewardBlock) public view returns (uint) {
        uint maxBlock = getBlockNumberOfMilestone(funiToken.getMaximumPeriodIndex() + 1);
        uint currentBlock = block.number > maxBlock ? maxBlock: block.number;

        require(currentBlock >= startBlock, 'MasterChef: currentBlock must be greater or equal startBlock');

        uint lastClaimPeriod = getPeriodIndexByBlockNumber(lastRewardBlock); 
        uint currentPeriod = getPeriodIndexByBlockNumber(currentBlock);
        
        uint startCalculationBlock = lastRewardBlock; 
        uint sum = 0; 
        
        for(uint i = lastClaimPeriod ; i  <= currentPeriod ; i++) { 
            uint nextBlock = i < currentPeriod ? getBlockNumberOfMilestone(i+1) : currentBlock;
            uint delta = nextBlock.sub(startCalculationBlock);
            sum = sum.add(delta.mul(getRewardPerBlock(i)));
            startCalculationBlock = nextBlock;
        }
        sum = sum.mul(funiToken.getMasterChefWeight()).div(100);
        return sum;
    }
    
    function setKeepPercent(uint _funiPoolPercent) public onlyOwner {
        require(_funiPoolPercent > 0 , "MasterChef::_funiPoolPercent: _funiPoolPercent must be greater 0");
        require(_funiPoolPercent <= 100 , "MasterChef::_funiPoolPercent: _funiPoolPercent must be less or equal 100");
        funiPoolPercent = _funiPoolPercent;
    }
}