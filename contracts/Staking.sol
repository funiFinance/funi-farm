// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';
// SyrupBar with Governance.
contract Staking is Ownable{
    address public funiToken; // swap token

    constructor(
        address _funiToken
    ) public {
        funiToken = _funiToken;
    }

    // just in case if not have enough FUNIs.
    function safeTransfer(address _to, uint256 _amount) public onlyOwner {
        uint256 funiBal = IBEP20(funiToken).balanceOf(address(this));
        if (_amount > funiBal) {
            IBEP20(funiToken).transfer(_to, funiBal);
        } else {
            IBEP20(funiToken).transfer(_to, _amount);
        }
    }
}