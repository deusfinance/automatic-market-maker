//Be name khoda

//SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/payment/PullPayment.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./Power.sol";

interface DEUSToken {
	function totalSupply() external view returns (uint256);

	function mint(address to, uint256 amount) external;
	function burn(address from, uint256 amount) external;
} 

contract AutomaticMarketMaker is Ownable, PullPayment, Power, ReentrancyGuard {

	using SafeMath for uint256;
	using SafeMath for uint32;

	DEUSToken public deusToken;
	uint256 public reserve;
	uint256 public firstSupply;
	uint256 public firstReserve;
	uint256 public reserveShiftAmount;
	address payable public daoWallet;

	uint32 public scale = 10**6;
	uint32 public cw = 0.4 * 10**6; 
	uint256 public daoShareScale = 10**18;
	uint256 public maxDaoShare = 0.15 * 10**18; // 15% * scale
	uint256 public daoTargetBalance = 500 * 10**18;

	function setDaoWallet(address payable _daoWallet) external onlyOwner{
		daoWallet = _daoWallet;
	}

	function withdraw(uint256 amount) external onlyOwner{
		daoWallet.transfer(amount);
	}

	function init(uint256 _firstReserve, uint256 _firstSupply) external onlyOwner{
		reserve = _firstReserve;
		firstReserve = _firstReserve;
		firstSupply = _firstSupply;
		reserveShiftAmount = reserve.mul(scale.sub(cw)).div(scale);
	}

	function setDaoShare(uint256 _maxDaoShare, uint256 _daoTargetBalance) external onlyOwner{
		maxDaoShare = _maxDaoShare;
		daoTargetBalance = _daoTargetBalance;
	}

	receive() external payable {
		// receive ether
	}

	constructor(address _deusToken) public ReentrancyGuard() {
		require(_deusToken != address(0), "Wrong argument");
		daoWallet = msg.sender;
		deusToken = DEUSToken(_deusToken);
	}

	function daoShare() public view returns (uint256){
		return maxDaoShare.sub(maxDaoShare.mul(daoWallet.balance).div(daoTargetBalance));
	}

	function _bancorCalculatePurchaseReturn(
		uint256 _supply,
		uint256 _connectorBalance,
		uint32 _connectorWeight,
		uint256 _depositAmount) internal view returns (uint256){
		// validate input
		require(_supply > 0 && _connectorBalance > 0 && _connectorWeight > 0 && _connectorWeight <= scale, "_bancorCalculatePurchaseReturn Error");

		// special case for 0 deposit amount
		if (_depositAmount == 0) {
			return 0;
		}

		uint256 result;
		uint8 precision;
		uint256 baseN = _depositAmount.add(_connectorBalance);
		(result, precision) = power(
		baseN, _connectorBalance, _connectorWeight, scale
		);
		uint256 newTokenSupply = _supply.mul(result) >> precision;
		return newTokenSupply.sub(_supply);
	}

	function calculatePurchaseReturn(uint256 etherAmount) public view returns (uint256) {

		etherAmount = etherAmount.mul(daoShareScale.sub(daoShare())).div(daoShareScale);

		uint256 supply = deusToken.totalSupply();
		
		if (supply < firstSupply){
			if  (reserve.add(etherAmount) > firstReserve){
				uint256 exteraEtherAmount = reserve.add(etherAmount).sub(firstReserve);
				uint256 tokenAmount = firstSupply.sub(supply);

				tokenAmount = tokenAmount.add(_bancorCalculatePurchaseReturn(firstSupply, firstReserve.sub(reserveShiftAmount), cw, exteraEtherAmount));
				return tokenAmount;
			}
			else{
				return supply.mul(etherAmount).div(reserve);
			}
		}else{
			return _bancorCalculatePurchaseReturn(supply, reserve.sub(reserveShiftAmount), cw, etherAmount);
		}
	}

	function buy(uint256 _tokenAmount) external payable nonReentrant() {
		uint256 tokenAmount = calculatePurchaseReturn(msg.value);
		require(tokenAmount >= _tokenAmount, 'price changed');

		uint256 daoEtherAmount = msg.value.mul(daoShare()).div(daoShareScale);
		reserve = reserve.add(msg.value.sub(daoEtherAmount));

		daoWallet.transfer(daoEtherAmount);
		deusToken.mint(msg.sender, tokenAmount);
	}

	function _bancorCalculateSaleReturn(
		uint256 _supply,
		uint256 _connectorBalance,
		uint32 _connectorWeight,
		uint256 _sellAmount) internal view returns (uint256){

		// validate input
		require(_supply > 0 && _connectorBalance > 0 && _connectorWeight > 0 && _connectorWeight <= scale && _sellAmount <= _supply, "_bancorCalculateSaleReturn Error");
		// special case for 0 sell amount
		if (_sellAmount == 0) {
			return 0;
		}
		// special case for selling the entire supply
		if (_sellAmount == _supply) {
			return _connectorBalance;
		}

		uint256 result;
		uint8 precision;
		uint256 baseD = _supply.sub(_sellAmount);
		(result, precision) = power(
			_supply, baseD, scale, _connectorWeight
		);
		uint256 oldBalance = _connectorBalance.mul(result);
		uint256 newBalance = _connectorBalance << precision;
		return oldBalance.sub(newBalance).div(result);
	}

	function calculateSaleReturn(uint256 tokenAmount) public view returns (uint256) {
		uint256 supply = deusToken.totalSupply();
		if (supply > firstSupply){
			if (firstSupply > supply.sub(tokenAmount)){
				uint256 exteraTokenAmount = firstSupply.sub(supply.sub(tokenAmount));
				uint256 etherAmount = reserve.sub(firstReserve);

				return etherAmount.add(firstReserve.mul(exteraTokenAmount).div(firstSupply));

			}else{
				return _bancorCalculateSaleReturn(supply, reserve.sub(reserveShiftAmount), cw, tokenAmount);
			}
		}else{
			return reserve.mul(tokenAmount).div(supply);
		}
	}

	function sell(uint256 tokenAmount, uint256 _etherAmount) external nonReentrant() {
		uint256 etherAmount = calculateSaleReturn(tokenAmount);

		require(etherAmount >= _etherAmount, 'price changed');

		_asyncTransfer(msg.sender, etherAmount);
		reserve = reserve.sub(etherAmount);
		deusToken.burn(msg.sender, tokenAmount);
	}
}

//Dar panah khoda