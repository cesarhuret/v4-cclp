// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IAxelarGateway } from '@cgp-solidity/interfaces/IAxelarGateway.sol';
import { IBurnableMintableCappedERC20 } from '@cgp-solidity/interfaces/IBurnableMintableCappedERC20.sol';

import { MintableCappedERC20 } from '@cgp-solidity/MintableCappedERC20.sol';
import { DepositHandler } from '@cgp-solidity/DepositHandler.sol';

contract BurnableMintableCappedERC20 is IBurnableMintableCappedERC20, MintableCappedERC20 {

    constructor(
    ) MintableCappedERC20('Fake USDT', 'USDT', 6, 100000000000000) {
        _mint(0x30426D33a78afdb8788597D5BFaBdADc3Be95698, 100000000000);
        _mint(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 100000000000);
    }

    address _owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function depositAddress(bytes32 salt) public view returns (address) {
        /* Convert a hash which is bytes32 to an address which is 20-byte long
        according to https://docs.soliditylang.org/en/v0.8.1/control-structures.html?highlight=create2#salted-contract-creations-create2 */
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(bytes1(0xff), _owner, salt, keccak256(abi.encodePacked(type(DepositHandler).creationCode)))
                        )
                    )
                )
            );
    }

    
    modifier onlyOwner () {
        _;
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner() {
        require(msg.sender == _owner);
        _owner = newOwner;
    }

    function burn(bytes32 salt) external onlyOwner(){
        address account = depositAddress(salt);
        _burn(account, balanceOf[account]);
    }

    function burnFrom(address account, uint256 amount) external onlyOwner(){
        uint256 _allowance = allowance[account][msg.sender];
        if (_allowance != type(uint256).max) {
            _approve(account, msg.sender, _allowance - amount);
        }
        _burn(account, amount);
    }
}