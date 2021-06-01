//Be name khoda
//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IWETH9 {
	function deposit() external payable;
	function withdraw(uint wad) external;
	function approve(address guy, uint wad) external returns (bool);
	function balanceOf(address account) external view returns (uint256);
}

interface IAMM {
	function buyFor(address user, uint256 _deusAmount, uint256 _wethAmount) external;
	function sellFor(address user, uint256 deusAmount, uint256 _wethAmount) external;
}

contract WethProxy{

	IWETH9 public wethToken;
	IAMM public AMM;

	constructor(address amm, address wethAddress) {
		AMM = IAMM(amm);
		wethToken = IWETH9(wethAddress);
		wethToken.approve(amm, 1e50);
	}

	function buy(uint256 _deusAmount, uint256 _wethAmount) public payable{
		wethToken.deposit{value:msg.value}();
		AMM.buyFor(msg.sender, _deusAmount, _wethAmount);
	}

	function sell(uint256 deusAmount, uint256 _wethAmount) public {
		AMM.sellFor(msg.sender, deusAmount, _wethAmount);
		uint256 wethAmount = wethToken.balanceOf(address(this)); 
		wethToken.withdraw(wethAmount);
		payable(msg.sender).transfer(wethAmount);
	}

}

//Dar panah khoda