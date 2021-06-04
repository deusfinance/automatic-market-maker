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
	function buyFor(address user, uint256 _dbEthAmount, uint256 _wethAmount) external;
	function sellFor(address user, uint256 dbEthAmount, uint256 _wethAmount) external;
}

interface IdbETH {
	function transferFrom(address sender, address recipient, uint256 amount) external;
}

contract WethProxy{

	IWETH9 public wethToken;
	IAMM public AMM;
	IdbETH public dbETH;

	constructor(address amm, address wethAddress, address _dbEth) {
		AMM = IAMM(amm);
		wethToken = IWETH9(wethAddress);
		dbETH = IdbETH(_dbEth);
		wethToken.approve(amm, 1e50);
	}

	function buy(address user, uint256 _dbEthAmount, uint256 _wethAmount) external payable {
		wethToken.deposit{value:msg.value}();
		AMM.buyFor(user, _dbEthAmount, _wethAmount);
	}

	function sell(address user, uint256 dbEthAmount, uint256 _wethAmount) external {
		dbETH.transferFrom(msg.sender, address(this), dbEthAmount);
		AMM.sellFor(msg.sender, dbEthAmount, _wethAmount);
		uint256 wethAmount = wethToken.balanceOf(address(this));
		wethToken.withdraw(wethAmount);
		payable(user).transfer(wethAmount);
	}

	receive() external payable {
		// receive ether
	}

}

//Dar panah khoda