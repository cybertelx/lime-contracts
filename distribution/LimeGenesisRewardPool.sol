// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// Note that this pool has no minter key of LIME (rewards).
// Instead, the governance will call LIME distributeReward method and send reward to this pool at the beginning.
contract LimeGenesisRewardPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // governance
    address public operator;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. LIME to distribute.
        uint256 lastRewardTime; // Last time that LIME distribution occurs.
        uint256 accLimePerShare; // Accumulated LIME per share, times 1e18. See below.
        bool isStarted; // if lastRewardBlock has passed
    }

    IERC20 public lime;
    address public USDCe;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The time when LIME mining starts.
    uint256 public poolStartTime;

    // The time when LIME mining ends.
    uint256 public poolEndTime;

    uint256 public limePerSecond = 0 ether; // TOTAL_REWARDS LIME / (1h * 60min * 60s)
    uint256 public runningTime = 0 hours; // 0 hours
    uint256 public TOTAL_REWARDS = 0 ether;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor(
        address _lime,
        address _USDCe
    ) public {
        if (_lime != address(0)) lime = IERC20(_lime);
        if (_USDCe != address(0)) USDCe = _USDCe;
        poolStartTime = 10**18; // not happening in a looooong time
        poolEndTime = 10**18;
        operator = msg.sender;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "LimeGenesisPool: caller is not the operator");
        _;
    }

    // if you wanna delay
    function setStart(uint256 _poolStartTime, uint256 _limePerSecond, uint256 _runningTime, uint256 _totalRewards) {
        require(poolStartTime < block.timestamp, "pool is already started");
        TOTAL_REWARDS = _totalRewards;
        runningTime = _runningTime;
        limePerSecond = _limePerSecond;
        poolStartTime = _poolStartTime;
        poolEndTime = _poolStartTime + _runningTime;
    }

    function checkPoolDuplicate(IERC20 _token) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token, "LimeGenesisPool: existing pool?");
        }
    }

    // Add a new token to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate,
        uint256 _lastRewardTime
    ) public onlyOperator {
        checkPoolDuplicate(_token);
        if (_withUpdate) {
            massUpdatePools();
        }
        if (block.timestamp < poolStartTime) {
            // chef is sleeping
            if (_lastRewardTime == 0) {
                _lastRewardTime = poolStartTime;
            } else {
                if (_lastRewardTime < poolStartTime) {
                    _lastRewardTime = poolStartTime;
                }
            }
        } else {
            // chef is cooking
            if (_lastRewardTime == 0 || _lastRewardTime < block.timestamp) {
                _lastRewardTime = block.timestamp;
            }
        }
        bool _isStarted = (_lastRewardTime <= poolStartTime) || (_lastRewardTime <= block.timestamp);
        poolInfo.push(PoolInfo({token: _token, allocPoint: _allocPoint, lastRewardTime: _lastRewardTime, accLimePerShare: 0, isStarted: _isStarted}));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's LIME allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOperator {
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(_allocPoint);
        }
        pool.allocPoint = _allocPoint;
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _fromTime, uint256 _toTime) public view returns (uint256) {
        if (_fromTime >= _toTime) return 0;
        if (_toTime >= poolEndTime) {
            if (_fromTime >= poolEndTime) return 0;
            if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(limePerSecond);
            return poolEndTime.sub(_fromTime).mul(limePerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(limePerSecond);
            return _toTime.sub(_fromTime).mul(limePerSecond);
        }
    }

    // View function to see pending LIME on frontend.
    function pendingLIME(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accLimePerShare = pool.accLimePerShare;
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _limeReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accLimePerShare = accLimePerShare.add(_limeReward.mul(1e18).div(tokenSupply));
        }
        return user.amount.mul(accLimePerShare).div(1e18).sub(user.rewardDebt);
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
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (tokenSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
        }
        if (totalAllocPoint > 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _limeReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accLimePerShare = pool.accLimePerShare.add(_limeReward.mul(1e18).div(tokenSupply));
        }
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens.
    function deposit(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accLimePerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safeLimeTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        if (_amount > 0) {
            pool.token.safeTransferFrom(_sender, address(this), _amount);
            if (address(pool.token) == USDCe) {
                user.amount = user.amount.add(_amount.mul(9900).div(10000));
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accLimePerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    // Withdraw LP tokens.
    function withdraw(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accLimePerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            safeLimeTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.token.safeTransfer(_sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accLimePerShare).div(1e18);
        emit Withdraw(_sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.token.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    // Safe LIME transfer function, just in case a rounding error causes pool to not have enough LIMEs.
    function safeLimeTransfer(address _to, uint256 _amount) internal {
        uint256 _limeBalance = lime.balanceOf(address(this));
        if (_limeBalance > 0) {
            if (_amount > _limeBalance) {
                lime.safeTransfer(_to, _limeBalance);
            } else {
                lime.safeTransfer(_to, _amount);
            }
        }
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 amount,
        address to
    ) external onlyOperator {
        if (block.timestamp < poolEndTime + 90 days) {
            // do not allow to drain core token (LIME or lps) if less than 90 days after pool ends
            require(_token != lime, "lime");
            uint256 length = poolInfo.length;
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.token, "pool.token");
            }
        }
        _token.safeTransfer(to, amount);
    }
}