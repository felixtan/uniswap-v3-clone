// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "./TestUtils.sol";
import "./ERC20Mintable.sol";
import "../src/UniswapV3Pool.sol";

contract UniswapV3PoolTest is Test, TestUtils {
    ERC20Mintable token0;
    ERC20Mintable token1;
    UniswapV3Pool pool;
    bool shouldTransferInCallback = true;

    // is run once
    function setUp() public {
        token0 = new ERC20Mintable("Ether", "ETH", 18);
        token1 = new ERC20Mintable("USDC", "USDC", 18);
    }

    // run before each test
    function setUpTestCase(TestCaseParams memory params) 
        internal 
        returns (uint256 poolBalance0, uint256 poolBalance1)
    {
        token0.mint(address(this), params.ethBalance);
        token1.mint(address(this), params.usdcBalance);

        pool = new UniswapV3Pool(
            address(token0), 
            address(token1), 
            params.currentSqrtP, 
            params.currentTick
        );

        if (params.mintLiqudity) {
            (poolBalance0, poolBalance1) = pool.mint(
                address(this), 
                params.lowerTick, 
                params.upperTick, 
                params.liquidity
            );
        }

        shouldTransferInCallback = params.shouldTransferInCallback;
    }

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1) public {
        if (shouldTransferInCallback) {
            token0.transfer(msg.sender, amount0);
            token1.transfer(msg.sender, amount1);
        }
    }

// 
// has correct  
// P and L.
    function testMintSuccess() public {
        TestCaseParams memory params = TestCaseParams({
            ethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            shouldTransferInCallback: true,
            mintLiqudity: true
        });

        (uint256 poolBalance0, uint256 poolBalance1) = setUpTestCase(params);

        uint256 expectedAmount0 = 0.998976618347425280 ether;
        uint256 expectedAmount1 = 5000 ether;

        // it should takes the correct amounts of tokens from us
        assertEq(poolBalance0, expectedAmount0);
        assertEq(poolBalance1, expectedAmount1);
        
        // it should transfer the tokens to the pool
        assertEq(token0.balanceOf(address(pool)), expectedAmount0);
        assertEq(token1.balanceOf(address(pool)), expectedAmount1);

        // it should create a position in the pool
        bytes32 key = keccak256(abi.encodePacked(address(this), params.lowerTick, params.upperTick));
        assertEq(pool.positions(key), params.liquidity);

        // it should initialize the lower tick
        (bool tickInitialized, uint128 tickLiquidity) = pool.ticks(params.lowerTick);
        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquidity);

        // it should initialize the upper tick
        (tickInitialized, tickLiquidity) = pool.ticks(params.upperTick);
        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquidity);

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(sqrtPriceX96, 5602277097478614198912276234240, "invalid current sqrt(P)");
        assertEq(tick, 85176, "invalid current tick");
        assertEq(pool.liquidity(), 1517882343751509868544, "invalid current liquidity");
    }

    function testExample() public {
        assertTrue(true);
    }
}