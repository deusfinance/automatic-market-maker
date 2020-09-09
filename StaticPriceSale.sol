//Be name khoda

//SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol";


// uncomment for mainnet
// interface IUniswapV2Pair {
//     function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
// }

// comment for mainnet
contract IUniswapV2Pair {
    function getReserves() public pure returns (uint112, uint112, uint32) {
        return (363556162544594959023586, 126706537078570, 1599552192);
    }
}

interface DEUSToken {
    function mint(address to, uint256 amount) external;
}

contract StaticPriceSale is Ownable{
	
	using SafeMath for uint112;
	using SafeMath for uint256;
	
    uint256 public endBlock;

    // comment for mainnet
	IUniswapV2Pair public pair = new IUniswapV2Pair();


	// UniswapV2 ETH/USDT pool address
	// uncomment for mainnet
	//IUniswapV2Pair pair = IUniswapV2Pair(address(0xdAC17F958D2ee523a2206206994597C13D831ec7));

	// DEUSToken contract address
    DEUSToken public deusToken;


	function setEndBlock(uint256 _endBlock) public onlyOwner{
        endBlock = _endBlock;
    }
    
	constructor(uint256 _endBlock, address _deusToken) public {
		endBlock = _endBlock;
		deusToken = DEUSToken(_deusToken);
    }

	// price of deus in Eth based on uniswap v2 ETH/USDT pool
	function price() public view returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

		// (1/0.63)*10**12 == 1587301587301
		// reserve1(USDT) has 6 decimals and reserve0(ETH) has 18 decimals, so 18-6 = 12
        return reserve1.mul(1587301587301).div(reserve0);
    }

	function buy() public payable{
		require(block.number <= endBlock, 'presale has been finished');

		uint256 tokenAmount = msg.value.mul(price());
		deusToken.mint(msg.sender, tokenAmount);
	}

	function withdraw(address payable to, uint256 amount) public onlyOwner{
		to.transfer(amount);
	}

}


//Dar panah khoda