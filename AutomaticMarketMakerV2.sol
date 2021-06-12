//Be name khoda
//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

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

	event Buy(address user, uint256 dbEthTokenAmount, uint256 wethAmount, uint256 feeAmount);
	event Sell(address user, uint256 wethAmount, uint256 dbEthTokenAmount, uint256 feeAmount);


	IERC20 public dbEthToken;
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
		daoFeeAmount = daoFeeAmount - amount;
		WETH.transfer(daoWallet, amount);
	}

	function withdrawTotalFee() external {
		withdrawFee(daoFeeAmount);
	}

	function addBlackList(address user) external onlyOperator {
		isBlackListed[user] = true;
	}

	function removeBlackList(address user) external onlyOperator {
		isBlackListed[user] = false;
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

	constructor(address _WETH, address _dbEthToken, address _power) ReentrancyGuard() {
		require(_WETH != address(0) && _dbETHToken != address(0) && _power != address(0), "Bad args");

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_setupRole(OPERATOR_ROLE, msg.sender);
		_setupRole(FEE_COLLECTOR_ROLE, msg.sender);

		daoWallet = msg.sender;
		WETH = IWETH(_WETH);
		dbEthToken = IERC20(_dbEthToken);
		Power = IPower(_power);
	}

	function _bancorCalculatePurchaseReturn(
		uint256 _supply,
		uint256 _connectorBalance,
		uint32 _connectorWeight,
		uint256 _depositAmount) internal view returns (uint256){
		// validate input
		require(_supply > 0 && _connectorBalance > 0 && _connectorWeight > 0 && _connectorWeight <= scale, "_bancorCalculateSaleReturn() Error");

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
		uint256 supply = dbEthToken.totalSupply();
		
		if (supply < firstSupply){
			if  (reserve + wethAmount > firstReserve){
				uint256 exteraDeusAmount = reserve + wethAmount - firstReserve;
				uint256 dbEthAmount = firstSupply - supply;

				dbEthAmount = dbEthAmount + _bancorCalculatePurchaseReturn(firstSupply, firstReserve - reserveShiftAmount, cw, exteraDeusAmount);
				return (dbEthAmount, feeAmount);
			}
			else{
				return (supply * wethAmount / reserve, feeAmount);
			}
		}else{
			return (_bancorCalculatePurchaseReturn(supply, reserve - reserveShiftAmount, cw, wethAmount), feeAmount);
		}
	}

	function buyFor(address user, uint256 _dbEthAmount, uint256 _wethAmount) public nonReentrant() {
		require(!isBlackListed[user], "freezed address");
		
		(uint256 dbEthAmount, uint256 feeAmount) = calculatePurchaseReturn(_wethAmount);
		require(dbEthAmount >= _dbEthAmount, 'price changed');

		reserve = reserve + _wethAmount - feeAmount;

		WETH.transferFrom(msg.sender, address(this), _wethAmount);
		dbEthToken.mint(user, dbEthAmount);

		daoFeeAmount = daoFeeAmount + feeAmount;

		emit Buy(user, dbEthAmount, _wethAmount, feeAmount);
	}

	function buy(uint256 dbEthTokenAmount, uint256 wethAmount) public {
		buyFor(msg.sender, dbEthTokenAmount, wethAmount);
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

	function calculateSaleReturn(uint256 dbEthAmount) public view returns (uint256, uint256) {
		uint256 supply = dbEthToken.totalSupply();
		uint256 returnAmount;

		if (supply > firstSupply) {
			if (firstSupply > supply - dbEthAmount) {
				uint256 exteraFutureAmount = firstSupply - (supply - dbEthAmount);
				uint256 wethAmount = reserve - firstReserve;
				returnAmount = wethAmount + (firstReserve * exteraFutureAmount / firstSupply);

			} else {
				returnAmount = _bancorCalculateSaleReturn(supply, reserve - reserveShiftAmount, cw, dbEthAmount);
			}
		} else {
			returnAmount = reserve * dbEthAmount / supply;
		}
		uint256 feeAmount = returnAmount * daoShare / daoShareScale;
		return (returnAmount - feeAmount, feeAmount);
	}

	function sellFor(address user, uint256 dbEthAmount, uint256 _wethAmount) public nonReentrant() {
		require(!isBlackListed[user], "freezed address");
		
		(uint256 wethAmount, uint256 feeAmount) = calculateSaleReturn(dbEthAmount);
		require(wethAmount >= _wethAmount, 'price changed');

		reserve = reserve - (wethAmount + feeAmount);
		dbEthToken.burn(msg.sender, dbEthAmount);
		WETH.transfer(msg.sender, wethAmount);

		daoFeeAmount = daoFeeAmount + feeAmount;

		emit Sell(user, wethAmount, dbEthAmount, feeAmount);
	}

	function sell(uint256 dbEthTokenAmount, uint256 wethAmount) public {
		sellFor(msg.sender, dbEthTokenAmount, wethAmount);
	}
}

//Dar panah khoda