// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";

interface FuniToken is IBEP20 {

    function getKeepPercent() external view returns(uint);

    function getInitialRewardPerBlock() external view returns(uint);

    function getMaximumPeriodIndex() external view returns(uint);

    function getBlockPerPeriod() external view returns(uint);
    
    function getMasterChefWeight() external view returns(uint);

    function getIncentiveWeight() external view returns(uint);

    function mint(address _to, uint256 _amount) external;

}