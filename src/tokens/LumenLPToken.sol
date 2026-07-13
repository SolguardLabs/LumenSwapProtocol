// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    LumenInsufficientAllowance,
    LumenInsufficientBalance,
    LumenZeroAddress,
    LumenZeroAmount
} from "../types/LumenErrors.sol";

contract LumenLPToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;

    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        string memory name_,
        string memory symbol_
    ) {
        name = name_;
        symbol = symbol_;
    }

    function approve(
        address spender,
        uint256 amount
    ) external returns (bool) {
        if (spender == address(0)) revert LumenZeroAddress();
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(
        address owner,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        uint256 currentAllowance = allowance[owner][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert LumenInsufficientAllowance();
            unchecked {
                allowance[owner][msg.sender] = currentAllowance - amount;
            }
            emit Approval(owner, msg.sender, allowance[owner][msg.sender]);
        }
        _transfer(owner, recipient, amount);
        return true;
    }

    function _transfer(
        address owner,
        address recipient,
        uint256 amount
    ) internal virtual {
        if (recipient == address(0)) revert LumenZeroAddress();
        if (amount == 0) revert LumenZeroAmount();
        _beforeTokenTransfer(owner, recipient, amount);

        uint256 ownerBalance = balanceOf[owner];
        if (ownerBalance < amount) revert LumenInsufficientBalance();
        unchecked {
            balanceOf[owner] = ownerBalance - amount;
            balanceOf[recipient] += amount;
        }
        emit Transfer(owner, recipient, amount);
    }

    function _mint(
        address recipient,
        uint256 amount
    ) internal virtual {
        if (recipient == address(0)) revert LumenZeroAddress();
        if (amount == 0) revert LumenZeroAmount();
        _beforeTokenTransfer(address(0), recipient, amount);
        totalSupply += amount;
        balanceOf[recipient] += amount;
        emit Transfer(address(0), recipient, amount);
    }

    function _burn(
        address owner,
        uint256 amount
    ) internal virtual {
        if (owner == address(0)) revert LumenZeroAddress();
        if (amount == 0) revert LumenZeroAmount();
        _beforeTokenTransfer(owner, address(0), amount);
        uint256 ownerBalance = balanceOf[owner];
        if (ownerBalance < amount) revert LumenInsufficientBalance();
        unchecked {
            balanceOf[owner] = ownerBalance - amount;
            totalSupply -= amount;
        }
        emit Transfer(owner, address(0), amount);
    }

    function _beforeTokenTransfer(
        address,
        address,
        uint256
    ) internal virtual { }
}
