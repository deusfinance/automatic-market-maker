//Be name khoda

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.1/contracts/access/AccessControl.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.1/contracts/security/ReentrancyGuard.sol";

interface IERC20 {
	function totalSupply() external view returns (uint256);
	function mint(address to, uint256 amount) external;
	function burn(address from, uint256 amount) external;
}

interface IPower {
	function power(uint256 _baseN, uint256 _baseD, uint32 _expN, uint32 _expD) external view returns (uint256, uint8);
}

interface IWETH {
	function transfer(address recipient, uint256 amount) external returns (bool);
	function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract AutomaticMarketMakerV2 is AccessControl, ReentrancyGuard {

	bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
	bytes32 public constant FEE_COLLECTOR_ROLE = keccak256("FEE_COLLECTOR_ROLE");

	event Buy(address user, uint256 deusTokenAmount, uint256 wethAmount, uint256 feeAmount);
	event Sell(address user, uint256 wethAmount, uint256 deusTokenAmount, uint256 feeAmount);


	IERC20 public deusToken;
	IWETH public WETH;
	IPower public Power;
	uint256 public reserve;
	uint256 public firstSupply;
	uint256 public firstReserve;
	uint256 public reserveShiftAmount;
	uint256 public daoFeeAmount;
	address public daoWallet;

	uint32 public scale = 10**6;
	uint32 public cw = 0.35 * 10**6; 


	uint256 public daoShare = 5 * 10**15;
	uint256 public daoShareScale = 10**18;

	mapping (address => bool) isBlackListed;

	modifier onlyOperator {
		require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not an operator");
		_;
	}

	function setDaoWallet(address _daoWallet) external onlyOperator {
		daoWallet = _daoWallet;
	}

	function withdrawWETH(uint256 amount, address to) external onlyOperator {
		WETH.transfer(to, amount);
	}

	function withdrawFee(uint256 amount) public {
		require(hasRole(FEE_COLLECTOR_ROLE, msg.sender), "Caller is not an FeeCollector");
		require(amount <= daoFeeAmount, "amount is bigger than daoFeeAmount");
		WETH.transfer(daoWallet, amount);
	}

	function withdrawTotalFee() external {
		withdrawFee(daoFeeAmount);
	}

	function addBlackList(address user) external onlyOperator {
		isBlackListed[user] = true;
	}

	function init(uint256 _firstReserve, uint256 _firstSupply) external onlyOperator {
		reserve = _firstReserve;
		firstReserve = _firstReserve;
		firstSupply = _firstSupply;
		reserveShiftAmount = reserve * (scale - cw) / scale;
	}

	function setDaoShare(uint256 _daoShare) external onlyOperator {
		daoShare = _daoShare;
	}

	receive() external payable {
		revert();
	}

	constructor(address _WETH, address _deusToken, address _power) ReentrancyGuard() {
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_setupRole(OPERATOR_ROLE, msg.sender);
		_setupRole(FEE_COLLECTOR_ROLE, msg.sender);

		daoWallet = msg.sender;
		WETH = IWETH(_WETH);
		deusToken = IERC20(_deusToken);
		Power = IPower(_power);
	}

	function _bancorCalculatePurchaseReturn(
		uint256 _supply,
		uint256 _connectorBalance,
		uint32 _connectorWeight,
		uint256 _depositAmount) internal view returns (uint256){
		// validate input
		require(_supply > 0 && _connectorBalance > 0 && _connectorWeight > 0 && _connectorWeight <= scale);

		// special case for 0 deposit amount
		if (_depositAmount == 0) {
			return 0;
		}

		uint256 result;
		uint8 precision;
		uint256 baseN = _depositAmount + _connectorBalance;
		(result, precision) = Power.power(baseN, _connectorBalance, _connectorWeight, scale);
		uint256 newTokenSupply = _supply * result >> precision;
		return newTokenSupply - _supply;
	}

	function calculatePurchaseReturn(uint256 wethAmount) public view returns (uint256, uint256) {

		uint256 feeAmount = wethAmount * daoShare / daoShareScale;
		wethAmount = wethAmount - feeAmount;
		uint256 supply = deusToken.totalSupply();
		
		if (supply < firstSupply){
			if  (reserve + wethAmount > firstReserve){
				uint256 exteraDeusAmount = reserve + wethAmount - firstReserve;
				uint256 deusAmount = firstSupply - supply;

				deusAmount = deusAmount + _bancorCalculatePurchaseReturn(firstSupply, firstReserve - reserveShiftAmount, cw, exteraDeusAmount);
				return (deusAmount, feeAmount);
			}
			else{
				return (supply * wethAmount / reserve, feeAmount);
			}
		}else{
			return (_bancorCalculatePurchaseReturn(supply, reserve - reserveShiftAmount, cw, wethAmount), feeAmount);
		}
	}

	function buyFor(address user, uint256 _deusAmount, uint256 _wethAmount) public nonReentrant() {
		require(!isBlackListed[user], "freezed address");
		
		(uint256 deusAmount, uint256 feeAmount) = calculatePurchaseReturn(_wethAmount);
		require(deusAmount >= _deusAmount, 'price changed');

		reserve = reserve + _wethAmount - feeAmount;

		WETH.transferFrom(msg.sender, address(this), _wethAmount);
		deusToken.mint(user, deusAmount);

		daoFeeAmount = daoFeeAmount + feeAmount;

		emit Buy(user, deusAmount, _wethAmount, feeAmount);
	}

	function buy(uint256 deusTokenAmount, uint256 wethAmount) public {
		buyFor(msg.sender, deusTokenAmount, wethAmount);
	}

	function _bancorCalculateSaleReturn(
		uint256 _supply,
		uint256 _connectorBalance,
		uint32 _connectorWeight,
		uint256 _sellAmount) internal view returns (uint256){

		// validate input
		require(_supply > 0 && _connectorBalance > 0 && _connectorWeight > 0 && _connectorWeight <= scale && _sellAmount <= _supply);
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
		uint256 baseD = _supply - _sellAmount;
		(result, precision) = Power.power(_supply, baseD, scale, _connectorWeight);
		uint256 oldBalance = _connectorBalance * result;
		uint256 newBalance = _connectorBalance << precision;
		return (oldBalance - newBalance) / result;
	}

	function calculateSaleReturn(uint256 deusAmount) public view returns (uint256, uint256) {
		uint256 supply = deusToken.totalSupply();
		uint256 returnAmount;

		if (supply > firstSupply) {
			if (firstSupply > supply - deusAmount) {
				uint256 exteraFutureAmount = firstSupply - (supply - deusAmount);
				uint256 wethAmount = reserve - firstReserve;
				returnAmount = wethAmount + (firstReserve * exteraFutureAmount / firstSupply);

			} else {
				returnAmount = _bancorCalculateSaleReturn(supply, reserve - reserveShiftAmount, cw, deusAmount);
			}
		} else {
			returnAmount = reserve * deusAmount / supply;
		}
		uint256 feeAmount = returnAmount * daoShare / daoShareScale;
		return (returnAmount - feeAmount, feeAmount);
	}

	function sellFor(address user, uint256 deusAmount, uint256 _wethAmount) public nonReentrant() {
		require(!isBlackListed[user], "freezed address");
		
		(uint256 wethAmount, uint256 feeAmount) = calculateSaleReturn(deusAmount);
		require(wethAmount >= _wethAmount, 'price changed');

		reserve = reserve - (wethAmount + feeAmount);
		deusToken.burn(msg.sender, deusAmount);
		WETH.transfer(msg.sender, wethAmount);

		daoFeeAmount = daoFeeAmount + feeAmount;

		emit Sell(user, wethAmount, deusAmount, feeAmount);
	}

	function sell(uint256 deusTokenAmount, uint256 wethAmount) public {
		sellFor(msg.sender, deusTokenAmount, wethAmount);
	}
}

//Dar panah khoda