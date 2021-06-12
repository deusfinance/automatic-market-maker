//Be name khoda

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface DEUSToken {
    function mint(address to, uint256 amount) external;
}

contract StaticPriceSale is Ownable{

    using SafeMath for uint112;
    using SafeMath for uint256;

    uint256 public endBlock;

    // UniswapV2 ETH/USDT pool address
    IUniswapV2Pair public pair;

    // DEUSToken contract address
    DEUSToken public deusToken;

    event ChangedEndBlock(uint256 oldEndBlock, uint256 newEndBlock);

    function setEndBlock(uint256 _endBlock) public onlyOwner{
        ChangedEndBlock(endBlock, _endBlock);
        endBlock = _endBlock;
    }

    constructor(uint256 _endBlock, address _deusToken, address _pair) public {
        require(_deusToken != address(0) && _pair != address(0), "Bad args");

        endBlock = _endBlock;
        deusToken = DEUSToken(_deusToken);
        pair = IUniswapV2Pair(_pair);
    }

    // price of deus in Eth based on uniswap v2 ETH/USDT pool
    function price() public view returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        // (1/0.63)*10**12 == 1587301587301
        // reserve1(USDT) has 6 decimals and reserve0(ETH) has 18 decimals, so 18-6 = 12
        return reserve1 * 1587301587301 / reserve0;
    }

    function buy() public payable{
        require(block.number <= endBlock, 'static price sale has been finished');

        uint256 tokenAmount = msg.value * price();
        deusToken.mint(msg.sender, tokenAmount);
    }

    function withdraw(address payable to, uint256 amount) public onlyOwner{
        to.transfer(amount);
    }

}

//Dar panah khoda