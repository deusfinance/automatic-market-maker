//Be name khoda

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract dbETHToken is ERC20, AccessControl{

	uint256 public currentPointIndex = 0;

	bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
	bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
	bytes32 public constant CURRENT_POINT_INDEX_SETTER_ROLE = keccak256("CURRENT_POINT_INDEX_SETTER_ROLE");

	constructor() ERC20("bonded ethereum", "dbETH") {
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);	
	}

	function mint(address to, uint256 amount) public {
        // Check that the calling account has the minter role
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        _mint(to, amount);
    }

	function burn(address from, uint256 amount) public {
        require(hasRole(BURNER_ROLE, msg.sender), "Caller is not a burner");
        _burn(from, amount);
    }

	function setCurrentPointIndex(uint256 _currentPointIndex) public {
		require(hasRole(CURRENT_POINT_INDEX_SETTER_ROLE, msg.sender), "Caller is not a currentPointIndex setter");
		currentPointIndex = _currentPointIndex;
	}

}
//Dar panah khoda