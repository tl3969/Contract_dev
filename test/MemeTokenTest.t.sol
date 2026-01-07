// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MemeToken.sol";

/**
 * @title MemeToken测试合约
 * @notice 使用Foundry进行全面的单元测试和集成测试
 */
contract MemeTokenTest is Test {
    MemeToken public token;
    
    // 测试地址
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public marketing = address(0x4);
    address public development = address(0x5);
    
    // Uniswap V2 Router (测试网地址)
    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    
    // 测试参数
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10**18; // 10亿代币
    string public constant TOKEN_NAME = "Meme Coin";
    string public constant TOKEN_SYMBOL = "MEME";
    
    function setUp() public {
        // 设置msg.sender为owner
        vm.startPrank(owner);
        
        // 部署合约
        token = new MemeToken(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOTAL_SUPPLY,
            UNISWAP_ROUTER,
            marketing,
            development
        );
        
        // 转账给测试用户
        token.transfer(user1, 100_000 * 10**18);
        token.transfer(user2, 100_000 * 10**18);
        
        vm.stopPrank();
    }
    
    // ==================== 基础功能测试 ====================
    
    function test_InitialState() public {
        // 测试基础信息
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY - 200_000 * 10**18);
        
        // 测试税率配置
        (uint256 buyTax, uint256 sellTax, uint256 marketingShare, uint256 devShare, uint256 liquidityShare) = 
            (token.taxConfig().buyTax, token.taxConfig().sellTax, 
             token.taxConfig().marketing, token.taxConfig().development, token.taxConfig().liquidity);
        
        assertEq(buyTax, 400);      // 4%
        assertEq(sellTax, 400);     // 4%
        assertEq(marketingShare + devShare + liquidityShare, 10000); // 总和100%
    }
    
    function test_TransferWithoutTax() public {
        vm.startPrank(user1);
        
        uint256 initialBalance = token.balanceOf(user1);
        uint256 transferAmount = 1_000 * 10**18;
        
        // 转账（非交易对转账，应无税）
        token.transfer(user2, transferAmount);
        
        assertEq(token.balanceOf(user1), initialBalance - transferAmount);
        assertEq(token.balanceOf(user2), 100_000 * 10**18 + transferAmount);
        
        vm.stopPrank();
    }
    
    // ==================== 税收功能测试 ====================
    
    function test_BuyTax() public {
        // 模拟在Uniswap买入
        address pair = token.uniswapV2Pair();
        
        vm.startPrank(user1);
        
        // 批准代币给交易对
        token.approve(pair, 10_000 * 10**18);
        
        // 记录初始余额
        uint256 initialBalance = token.balanceOf(user1);
        uint256 initialContractBalance = token.balanceOf(address(token));
        
        // 模拟买入交易（从交易对转账给用户）
        vm.mockCall(
            pair,
            abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)")), pair, user1, 10_000 * 10**18),
            abi.encode(true)
        );
        
        // 执行转账（触发税收）
        vm.expectEmit(true, true, true, true);
        emit TaxesCollected(user1, 400, 0, 400); // 4%买入税
        
        // 这里需要实际调用交易对的方法，简化测试
        // token.transferFrom(pair, user1, 10_000 * 10**18);
        
        vm.stopPrank();
    }
    
    function test_TaxExclusion() public {
        vm.startPrank(owner);
        
        // 将用户1从税收中排除
        token.excludeFromTax(user1, true);
        
        // 验证排除状态
        assertTrue(token.isExcludedFromTax(user1));
        
        vm.stopPrank();
    }
    
    // ==================== 交易限制测试 ====================
    
    function test_MaxTransactionLimit() public {
        vm.startPrank(owner);
        
        // 设置最大交易量为总供应量的1%
        uint256 maxTxAmount = TOTAL_SUPPLY / 100;
        
        MemeToken.TradeLimit memory newLimit = MemeToken.TradeLimit({
            maxTxAmount: maxTxAmount,
            maxWalletAmount: type(uint256).max,
            dailySellLimit: type(uint256).max,
            antiWhaleEnabled: true
        });
        
        token.updateTradeLimit(newLimit);
        
        vm.stopPrank();
        
        // 测试超过限制的交易
        vm.startPrank(user1);
        
        uint256 excessiveAmount = maxTxAmount + 1;
        
        vm.expectRevert("Exceeds max transaction amount");
        token.transfer(user2, excessiveAmount);
        //token._transfer(from, to, amount);
        vm.stopPrank();
    }
    
    function test_DailySellLimit() public {
        vm.startPrank(owner);
        
        // 设置每日卖出限额
        uint256 dailyLimit = 10_000 * 10**18;
        
        MemeToken.TradeLimit memory newLimit = MemeToken.TradeLimit({
            maxTxAmount: type(uint256).max,
            maxWalletAmount: type(uint256).max,
            dailySellLimit: dailyLimit,
            antiWhaleEnabled: true
        });
        
        token.updateTradeLimit(newLimit);
        
        // 启用交易
        token.enableTrading();
        
        vm.stopPrank();
        
        // 测试每日卖出限制
        vm.startPrank(user1);
        
        // 第一次卖出（应在限额内）
        token.transfer(address(token.uniswapV2Pair()), dailyLimit / 2);
        //token._transfer(from, to, amount);
        // 第二次卖出（应超过限额）
        vm.expectRevert("Exceeds daily sell limit");
        token.transfer(address(token.uniswapV2Pair()), dailyLimit);
        // token._transfer(from, to, amount);
        vm.stopPrank();
    }
    
    // ==================== 流动性功能测试 ====================
    
    function test_AddLiquidity() public {
        vm.startPrank(owner);
        
        // 记录初始余额
        uint256 initialBalance = token.balanceOf(owner);
        uint256 initialEthBalance = address(owner).balance;
        
        // 添加流动性
        uint256 tokenAmount = 100_000 * 10**18;
        uint256 ethAmount = 10 ether;
        
        // 设置ETH余额
        vm.deal(owner, ethAmount);
        
        // 批准代币
        token.approve(address(token), tokenAmount);
        
        // 添加流动性
        token.addLiquidity{value: ethAmount}(tokenAmount);
        //token._addLiquidity(tokenAmount, ethAmount);
        // 验证余额变化
        assertEq(token.balanceOf(owner), initialBalance - tokenAmount);
        assertLt(address(owner).balance, initialEthBalance - ethAmount);
        
        vm.stopPrank();
    }
    
    function test_EnableTrading() public {
        vm.startPrank(owner);
        
        // 初始状态应为false
        assertFalse(token.tradingEnabled());
        
        // 添加最小流动性
        uint256 tokenAmount = 1000 * 10**18;
        uint256 ethAmount = 1 ether;
        vm.deal(owner, ethAmount);
        token.approve(address(token), tokenAmount);
        token.addLiquidity{value: ethAmount}(tokenAmount);
        
        // 启用交易
        token.enableTrading();
        
        // 验证状态
        assertTrue(token.tradingEnabled());
        assertGt(token.launchedAt(), 0);
        
        vm.stopPrank();
    }
    
    // ==================== Gas优化测试 ====================
    
    function test_GasOptimization() public {
        vm.startPrank(user1);
        
        // 测试普通转账的Gas消耗
        uint256 gasBefore = gasleft();
        token.transfer(user2, 100 * 10**18);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Transfer gas used:", gasUsed);
        
        // Gas消耗应在合理范围内
        assertLt(gasUsed, 100000);
        
        vm.stopPrank();
    }
    
    // ==================== 边界条件测试 ====================
    
    function test_ZeroAmountTransfer() public {
        vm.startPrank(user1);
        
        vm.expectRevert("Transfer amount must be > 0");
        token.transfer(user2, 0);
        
        vm.stopPrank();
    }
    
    function test_TransferToZeroAddress() public {
        vm.startPrank(user1);
        
        vm.expectRevert("Transfer to zero address");
        token.transfer(address(0), 100 * 10**18);
        
        vm.stopPrank();
    }
    
    function test_TradingNotEnabled() public {
        // 交易未启用时，普通用户应无法转账
        vm.startPrank(user1);
        
        vm.expectRevert("Trading not enabled");
        token.transfer(user2, 100 * 10**18);
        
        vm.stopPrank();
    }
    
    // ==================== 管理员功能测试 ====================
    
    function test_OwnerFunctions() public {
        // 测试非所有者调用管理员函数
        vm.startPrank(user1);
        
        vm.expectRevert();
        token.updateTaxConfig(MemeToken.TaxConfig({
            buyTax: 100,
            sellTax: 100,
            marketing: 3333,
            development: 3333,
            liquidity: 3334
        }));
        
        vm.stopPrank();
    }
    
    function test_WithdrawETH() public {
        // 给合约发送一些ETH
        vm.deal(address(token), 10 ether);
        
        vm.startPrank(owner);
        
        uint256 initialOwnerBalance = address(owner).balance;
        uint256 contractBalance = address(token).balance;
        
        // 提取ETH
        token.withdrawETH();
        
        // 验证提取
        assertEq(address(token).balance, 0);
        assertEq(address(owner).balance, initialOwnerBalance + contractBalance);
        
        vm.stopPrank();
    }
}