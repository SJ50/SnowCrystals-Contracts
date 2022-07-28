// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockBtc is ERC20 {
    constructor() public ERC20("Mock BTC", "M.BTC") {
        _mint(msg.sender, 100 * 10**18);
    }
}
