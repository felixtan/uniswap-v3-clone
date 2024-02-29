// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
    Pool = an exchange market between two tokens
        - we need their addresses
        - store liquidity L as a constant

    Liquidity positions
        - need to map the position to the position data

    Ticks = demarcation within a price range; corresponds to price and has an index
        - need mapping of ticks to tick data
        - store limits as constants

    Current price and tick
        -  store as mutable variable
 */

error InvalidTickRange();
error ZeroLiquidity();
error InsufficientInputAmount();

library Tick {
    struct Info {
        bool initialized;
        uint128 liquidity;
    }

    function update(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        uint128 liquidityDelta
    ) internal {
        Tick.Info storage tickInfo = self[tick];
        uint128 liquidityBefore = tickInfo.liquidity;
        uint128 liquidityAfter = liquidityBefore + liquidityDelta;

        // initializes a tick if it has 0 liquidity
        if (liquidityBefore == 0) {
            tickInfo.initialized = true;
        }

        tickInfo.liquidity = liquidityAfter;
    }
}

library Position {
    struct Info {
        uint128 liquidity;
    }

    function update(Info storage self, uint128 liquidityDelta) internal {
        uint128 liquidityBefore = self.liquidity;
        uint128 liquidityAfter = liquidityBefore + liquidityDelta;
        self.liquidity = liquidityAfter;
    }

    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        int24 lowerTick,
        int24 upperTick
    ) internal view returns (Position.Info storage position) {
        position = self[
            // hash the three to make storing data cheaper: when hashed, every key will take 
            // 32 bytes, instead of 96 bytes when owner, lowerTick, and upperTick are separate keys
            keccak256(abi.encodePacked(owner, lowerTick, upperTick))
        ];
    }
}

contract IUniswapV3MintCallback {
    constructor(address _sender) {}

    function uniswapV3MintCallback(uint256 _amount0, uint256 _amount1) public {}
}

contract UniswapV3Pool {
    // "using A for B" lets you extend type B with functions from library contract A
    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    // https://ethereum.stackexchange.com/questions/144793/why-does-uniswap-v3-use-ticks-887272-887272-to-represent-the-price-range-0-%E2%88%9E
    // 887272 is just enough to produce a sqrtPriceX96 that is still lower than the maximum value allowed by the type uint160
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    // pool tokens
    address public immutable token0;
    address public immutable token1;

    // packing price and tick info to be read together
    struct Slot0 {
        // Uniswap uses Q64.96 number to store sqrt of price
        uint160 sqrtPriceX96;
        int24 tick;
    }
    Slot0 public slot0;

    // Amount of liquidity L
    uint128 public liquidity;

    // Ticks info
    mapping(int24 => Tick.Info) public ticks;

    mapping(bytes32 => Position.Info) public positions;

    event Mint(address indexed _from, address indexed _owner, int24 _lowerTick, int24 _upperTick, uint128 _amount, uint256 _amount0, uint256 _amount1);

    constructor(address _token0, address _token1, uint160 sqrtPriceX96, int24 tick) {
        token0 = _token0;
        token1 = _token1;
        slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick});
    }

    // owner = address of the liquidity provider
    // lowerTick, upperTick = price range
    // amount = liquidity amount L
    function mint(
        address owner,
        int24 lowerTick,
        int24 upperTick,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1) {
        // validate given tick range
        if (
            lowerTick >= upperTick ||
            lowerTick < MIN_TICK ||
            upperTick > MAX_TICK
        ) {
            revert InvalidTickRange();
        }

        // validate given liquidity amount
        if (amount == 0) {
            revert ZeroLiquidity();
        }

        ticks.update(lowerTick, amount);
        ticks.update(upperTick, amount);

        Position.Info storage position = positions.get(
            owner,
            lowerTick,
            upperTick
        );
        position.update(amount);

        // amounts that user must deposit
        amount0 = 0.998976618347425280 ether;
        amount1 = 5000 ether;

        // update liquidity
        liquidity += uint128(amount);

        // transfer tokens from user to pool
        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(
            amount0,
            amount1
        );
        if (amount0 > 0 && balance0Before + amount0 > balance0())
            revert InsufficientInputAmount();
        if (amount1 > 0 && balance1Before + amount1 > balance1())
            revert InsufficientInputAmount();

        // good practice to fire an event whenever the contract’s state is changed to let blockchain explorer know when this happened
        emit Mint(msg.sender, owner, lowerTick, upperTick, amount, amount0, amount1);
    }

    function balance0() internal returns (uint256 balance) {
        balance = IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal returns (uint256 balance) {
        balance = IERC20(token1).balanceOf(address(this));
    }
}