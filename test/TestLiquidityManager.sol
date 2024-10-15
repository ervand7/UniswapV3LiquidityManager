// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../src/LiquidityManager.sol";
import "forge-std/Test.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Interface for WETH9 to allow deposit function
interface IWETH is IERC20 {
    function deposit() external payable;
}

contract LiquidityManagerTest is Test {
    uint256 private constant MAINNET_BLOCK = 15000000;
    string private constant MAINNET_RPC_URL = "https://eth.llamarpc.com";
    address private constant USER = address(1);
    uint256 private constant DAI_AMOUNT = 100000 ether;
    uint256 private constant WETH_AMOUNT = 100 ether;
    uint256 private constant DAI_BALANCE_SLOT = 2;
    address private constant DAI_MAINNET_ADDR = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WETH_MAINNET_ADDR = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant POSITION_MANAGER_MAINNET_ADDR = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address private constant UNISWAP_V3_POOL_MAINNET_ADDR = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;

    LiquidityManager liquidityManager;
    INonfungiblePositionManager positionManager;
    IUniswapV3Pool pool;

    IERC20 DAI = IERC20(DAI_MAINNET_ADDR);
    IWETH WETH9 = IWETH(WETH_MAINNET_ADDR);

    function setDAIBalance(address account, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(account, uint256(DAI_BALANCE_SLOT)));
        vm.store(address(DAI), slot, bytes32(amount));
    }

    function setWETHBalance(address account, uint256 amount) internal {
        // Set ETH balance
        vm.deal(account, amount);

        // Simulate user wrapping ETH into WETH
        vm.startPrank(account);
        WETH9.deposit{value: amount}();
        vm.stopPrank();
    }

    function approveTokens(address account, uint256 daiAmount, uint256 wethAmount) internal {
        vm.startPrank(account);
        DAI.approve(address(liquidityManager), daiAmount);
        WETH9.approve(address(liquidityManager), wethAmount);
        vm.stopPrank();
    }

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL, MAINNET_BLOCK);

        positionManager = INonfungiblePositionManager(POSITION_MANAGER_MAINNET_ADDR);
        pool = IUniswapV3Pool(UNISWAP_V3_POOL_MAINNET_ADDR);
        liquidityManager = new LiquidityManager(positionManager, pool);

        setDAIBalance(USER, DAI_AMOUNT);
        setWETHBalance(USER, WETH_AMOUNT);

        approveTokens(USER, DAI_AMOUNT, WETH_AMOUNT);
    }

    function testAddLiquidity() public {
        uint256 width = 100;

        vm.prank(USER);
        (uint256 tokenId, uint128 liquidity, uint256 amount0Used, uint256 amount1Used) =
            liquidityManager.addLiquidity(pool, DAI_AMOUNT, WETH_AMOUNT, width);

        assertGt(uint256(liquidity), 0, "Liquidity should be greater than 0");
        assertGt(tokenId, 0, "Token ID should be greater than 0");
        assertLe(amount0Used, DAI_AMOUNT, "Used more amount0 than provided");
        assertLe(amount1Used, WETH_AMOUNT, "Used more amount1 than provided");
    }

    function testAddLiquidityWithDifferentWidths() public {
        uint256[] memory widths = new uint256[](3);
        widths[0] = 10;
        widths[1] = 50;
        widths[2] = 100;

        // Take less amounts not to be beyond allowed amount
        uint256 daiAmount = DAI_AMOUNT / 10;
        uint256 wethAmount = WETH_AMOUNT / 10;

        for (uint256 i = 0; i < widths.length; i++) {
            vm.prank(USER);
            (uint256 tokenId, uint128 liquidity,,) =
                liquidityManager.addLiquidity(pool, daiAmount, wethAmount, widths[i]);

            assertGt(uint256(liquidity), 0, "Liquidity should be greater than 0");
            assertGt(tokenId, 0, "Token ID should be greater than 0");
        }
    }

    function testAddLiquidityWithZeroAmounts() public {
        uint256 width = 1;

        vm.prank(USER);
        vm.expectRevert("Input amount should not be zero");
        liquidityManager.addLiquidity(pool, 0, 0, width);
    }

    function testAddLiquidityWithInsufficientBalance() public {
        uint256 width = 1;

        // Reduce USER's DAI balance
        setDAIBalance(USER, DAI_AMOUNT / 2);

        vm.prank(USER);
        vm.expectRevert();
        liquidityManager.addLiquidity(pool, DAI_AMOUNT, WETH_AMOUNT, width);
    }

    function testRefundUnusedTokens() public {
        uint256 width = 100;

        vm.prank(USER);
        (,, uint256 amount0Used, uint256 amount1Used) =
            liquidityManager.addLiquidity(pool, DAI_AMOUNT, WETH_AMOUNT, width);

        uint256 daiBalanceAfter = DAI.balanceOf(USER);
        uint256 wethBalanceAfter = WETH9.balanceOf(USER);

        // Expected balances after refund
        uint256 expectedDaiBalance = DAI_AMOUNT - amount0Used;
        uint256 expectedWethBalance = WETH_AMOUNT - amount1Used;

        // Allow for a small tolerance due to rounding
        uint256 tolerance = 1e14; // 0.0001 ETH

        assertEq(daiBalanceAfter, expectedDaiBalance, "DAI refund amount incorrect");
        assertApproxEqAbs(wethBalanceAfter, expectedWethBalance, tolerance, "WETH refund amount incorrect");
    }

    function testAddLiquidityWithInvalidWidth() public {
        uint256 invalidWidth = uint256(type(int24).max) + 1; // Exceeds int24 max value

        vm.prank(USER);
        vm.expectRevert(); // Expecting a revert due to invalid tick calculation
        liquidityManager.addLiquidity(pool, DAI_AMOUNT, WETH_AMOUNT, invalidWidth);
    }

    function testAddLiquidityAtEdgeTicks() public {
        uint256 width = uint256(type(int24).max);

        vm.prank(USER);
        vm.expectRevert("tickLower must be less than tickUpper");
        liquidityManager.addLiquidity(pool, DAI_AMOUNT, WETH_AMOUNT, width);
    }

    function testInsufficientBalance() public {
        uint256 width = 100;

        vm.prank(USER);
        (uint256 tokenId,,,) = liquidityManager.addLiquidity(pool, DAI_AMOUNT, WETH_AMOUNT, width);

        assertEq(positionManager.ownerOf(tokenId), USER, "Token owner should be USER");
    }

    function testPartialFills() public {
        uint256 width = 1;
        uint256 largeDAIAmount = DAI_AMOUNT * 10; // Exaggerated amount

        vm.prank(USER);
        vm.expectRevert();
        liquidityManager.addLiquidity(pool, largeDAIAmount, WETH_AMOUNT, width);
    }

    function testAddLiquidityWithoutApproval() public {
        uint256 width = 1;

        // Do not approve tokens this time
        vm.startPrank(USER);
        DAI.approve(address(liquidityManager), 0);
        WETH9.approve(address(liquidityManager), 0);
        vm.stopPrank();

        vm.prank(USER);
        vm.expectRevert();
        liquidityManager.addLiquidity(pool, DAI_AMOUNT, WETH_AMOUNT, width);
    }
}
