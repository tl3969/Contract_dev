// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MemeToken - SHIB风格的去中心化Meme代币
 * @notice 包含交易税、流动性池集成和交易限制功能的ERC20代币
 * @dev 关键特性：
 * 1. 可配置的买入/卖出交易税
 * 2. 税收自动分配给营销、开发和流动性池
 * 3. 防鲸鱼机制和交易限制
 * 4. Uniswap V2流动性池集成
 * 5. 完全可升级的配置参数
 */
contract MemeToken is ERC20, Ownable, ReentrancyGuard {
    // ============================ 常量定义 ============================
    uint256 public constant TAX_DENOMINATOR = 10000; // 税率分母，10000 = 100%
    uint256 public constant MAX_TAX_RATE = 1500;     // 最大税率15%
    uint256 public constant MIN_LIQUIDITY = 1000 ether; // 最小流动性
    
    // ============================ 状态变量 ============================
    
    // 税率配置
    struct TaxConfig {
        uint256 buyTax;      // 买入税率（基础10000）
        uint256 sellTax;     // 卖出税率（基础10000）
        uint256 marketing;   // 营销分配比例
        uint256 development; // 开发分配比例
        uint256 liquidity;   // 流动性分配比例
    }
    
    TaxConfig public taxConfig = TaxConfig({
        buyTax: 400,        // 4% 买入税
        sellTax: 400,       // 4% 卖出税
        marketing: 4000,    // 40% 给营销
        development: 3000,  // 30% 给开发
        liquidity: 3000     // 30% 给流动性
    });
    
    // 交易限制配置
    struct TradeLimit {
        uint256 maxTxAmount;      // 最大单笔交易量
        uint256 maxWalletAmount;  // 最大持币量
        uint256 dailySellLimit;   // 每日卖出限额
        bool antiWhaleEnabled;    // 防鲸鱼开关
    }
    
    TradeLimit public tradeLimit = TradeLimit({
        maxTxAmount: type(uint256).max,
        maxWalletAmount: type(uint256).max,
        dailySellLimit: type(uint256).max,
        antiWhaleEnabled: true
    });
    
    // 地址映射
    address public marketingWallet;
    address public developmentWallet;
    address public liquidityWallet;
    address public uniswapV2Pair;
    
    // 排除列表
    mapping(address => bool) public isExcludedFromTax;
    mapping(address => bool) public isExcludedFromLimits;
    
    // 交易状态
    bool public tradingEnabled = false;
    bool public swapEnabled = true;
    uint256 public launchedAt;
    
    // 每日卖出记录
    struct DailySellRecord {
        uint256 amount;
        uint256 timestamp;
    }
    mapping(address => DailySellRecord) public dailySells;
    
    // Uniswap V2 Router
    IUniswapV2Router02 public immutable uniswapV2Router;
    
    // 事件定义
    event TradingEnabled(uint256 timestamp);
    event TaxesCollected(address indexed user, uint256 buyTax, uint256 sellTax, uint256 totalTax);
    event TaxConfigUpdated(TaxConfig newConfig);
    event TradeLimitUpdated(TradeLimit newLimit);
    event WalletsUpdated(address marketing, address development, address liquidity);
    event LiquidityAdded(uint256 tokenAmount, uint256 ethAmount, uint256 liquidity);
    event LiquidityRemoved(uint256 liquidity, uint256 tokenAmount, uint256 ethAmount);
    
    // ============================ 构造函数 ============================
    
    /**
     * @dev 初始化Meme代币合约
     * @param _name 代币名称
     * @param _symbol 代币符号
     * @param _totalSupply 总供应量（包含小数位）
     * @param _router  Uniswap V2 Router地址
     * @param _marketing 营销钱包地址
     * @param _development 开发钱包地址
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        address _router,
        address _marketing,
        address _development
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_totalSupply > 0, "Total supply must be > 0");
        require(_router != address(0), "Router cannot be zero address");
        require(_marketing != address(0), "Marketing wallet cannot be zero address");
        require(_development != address(0), "Development wallet cannot be zero address");
        
        // 设置总供应量
        _mint(msg.sender, _totalSupply);
        
        // 初始化钱包地址
        marketingWallet = _marketing;
        developmentWallet = _development;
        liquidityWallet = address(this);
        
        // 初始化Uniswap Router
        uniswapV2Router = IUniswapV2Router02(_router);
        
        // 创建Uniswap交易对
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            uniswapV2Router.WETH()
        );
        
        // 设置初始排除列表
        _setInitialExclusions();
        
        // 设置初始交易限制
        _setInitialLimits(_totalSupply);
    }
    
    // ============================ 内部函数 ============================
    
    /**
     * @dev 设置初始排除列表
     */
    function _setInitialExclusions() private {
        isExcludedFromTax[owner()] = true;
        isExcludedFromTax[address(this)] = true;
        isExcludedFromTax[marketingWallet] = true;
        isExcludedFromTax[developmentWallet] = true;
        isExcludedFromTax[uniswapV2Pair] = true;
        
        isExcludedFromLimits[owner()] = true;
        isExcludedFromLimits[address(this)] = true;
        isExcludedFromLimits[uniswapV2Pair] = true;
    }
    
    /**
     * @dev 设置初始交易限制
     * @param totalSupply 总供应量
     */
    function _setInitialLimits(uint256 totalSupply) private {
        tradeLimit.maxTxAmount = totalSupply / 100;      // 1% 最大交易量
        tradeLimit.maxWalletAmount = totalSupply / 50;   // 2% 最大持币量
        tradeLimit.dailySellLimit = totalSupply / 200;   // 0.5% 每日卖出限额
    }
    
    /**
     * @dev 重写ERC20转账函数，添加税收和限制逻辑
     * @param from 发送方地址
     * @param to 接收方地址
     * @param amount 转账金额
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override nonReentrant {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(amount > 0, "Transfer amount must be > 0");
        
        // 检查交易是否启用（仅对非排除地址）
        if (!isExcludedFromLimits[from] && !isExcludedFromLimits[to]) {
            require(tradingEnabled, "Trading not enabled");
        }
        
        // 应用交易限制
        _applyTradeLimits(from, to, amount);
        
        // 计算并应用税收
        uint256 taxAmount = _calculateTax(from, to, amount);
        uint256 transferAmount = amount - taxAmount;
        
        // 执行基础转账
        super._transfer(from, to, transferAmount);
        
        // 收取税收
        if (taxAmount > 0) {
            super._transfer(from, address(this), taxAmount);
            _distributeTax(taxAmount);
        }
        
        // 更新每日卖出记录
        _updateDailySellRecord(from, to, amount);
    }
    
    /**
     * @dev 计算交易税收
     * @param from 发送方
     * @param to 接收方
     * @param amount 交易金额
     * @return taxAmount 税收金额
     */
    function _calculateTax(
        address from,
        address to,
        uint256 amount
    ) private view returns (uint256 taxAmount) {
        // 如果任一地址排除税收，则不收税
        if (isExcludedFromTax[from] || isExcludedFromTax[to]) {
            return 0;
        }
        
        bool isBuy = from == uniswapV2Pair;
        bool isSell = to == uniswapV2Pair;
        
        if (isBuy) {
            taxAmount = (amount * taxConfig.buyTax) / TAX_DENOMINATOR;
        } else if (isSell) {
            taxAmount = (amount * taxConfig.sellTax) / TAX_DENOMINATOR;
        }
        
        return taxAmount;
    }
    
    /**
     * @dev 分配税收到各个钱包
     * @param totalTax 总税收金额
     */
    function _distributeTax(uint256 totalTax) private {
        uint256 marketingTax = (totalTax * taxConfig.marketing) / TAX_DENOMINATOR;
        uint256 developmentTax = (totalTax * taxConfig.development) / TAX_DENOMINATOR;
        uint256 liquidityTax = totalTax - marketingTax - developmentTax;
        
        // 转账到营销和开发钱包
        if (marketingTax > 0) {
            super._transfer(address(this), marketingWallet, marketingTax);
        }
        if (developmentTax > 0) {
            super._transfer(address(this), developmentWallet, developmentTax);
        }
        
        // 流动性税收保留在合约中
        if (liquidityTax > 0 && swapEnabled) {
            _addLiquidityAutomatically(liquidityTax);
        }
    }
    
    /**
     * @dev 自动添加流动性
     * @param tokenAmount 代币数量
     */
    function _addLiquidityAutomatically(uint256 tokenAmount) private {
        uint256 half = tokenAmount / 2;
        uint256 otherHalf = tokenAmount - half;
        
        // 将一半代币换成ETH
        uint256 initialEthBalance = address(this).balance;
        _swapTokensForEth(half);
        uint256 newEthBalance = address(this).balance - initialEthBalance;
        
        // 添加流动性
        if (newEthBalance > 0) {
            _addLiquidity(otherHalf, newEthBalance);
        }
    }
    
    /**
     * @dev 将代币兑换为ETH
     * @param tokenAmount 代币数量
     */
    function _swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }
    
    /**
     * @dev 添加流动性
     * @param tokenAmount 代币数量
     * @param ethAmount ETH数量
     */
    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            liquidityWallet,
            block.timestamp
        );
        
        emit LiquidityAdded(tokenAmount, ethAmount, tokenAmount);
    }
    
    /**
     * @dev 应用交易限制
     * @param from 发送方
     * @param to 接收方
     * @param amount 交易金额
     */
    function _applyTradeLimits(
        address from,
        address to,
        uint256 amount
    ) private view {
        // 如果地址排除限制，直接返回
        if (isExcludedFromLimits[from] || isExcludedFromLimits[to]) {
            return;
        }
        
        // 检查最大交易量
        require(
            amount <= tradeLimit.maxTxAmount,
            "Exceeds max transaction amount"
        );
        
        // 如果是买入，检查最大持币量
        if (from == uniswapV2Pair) {
            require(
                balanceOf(to) + amount <= tradeLimit.maxWalletAmount,
                "Exceeds max wallet amount"
            );
        }
        
        // 如果是卖出，检查每日限额
        if (to == uniswapV2Pair && tradeLimit.antiWhaleEnabled) {
            _checkDailySellLimit(from, amount);
        }
    }
    
    /**
     * @dev 检查每日卖出限额
     * @param seller 卖出者地址
     * @param amount 卖出金额
     */
    function _checkDailySellLimit(address seller, uint256 amount) private view {
        DailySellRecord memory record = dailySells[seller];
        uint256 currentDay = block.timestamp / 1 days;
        uint256 recordDay = record.timestamp / 1 days;
        
        uint256 soldToday = (currentDay == recordDay) ? record.amount : 0;
        
        require(
            soldToday + amount <= tradeLimit.dailySellLimit,
            "Exceeds daily sell limit"
        );
    }
    
    /**
     * @dev 更新每日卖出记录
     * @param from 发送方
     * @param to 接收方
     * @param amount 交易金额
     */
    function _updateDailySellRecord(
        address from,
        address to,
        uint256 amount
    ) private {
        if (to == uniswapV2Pair) {
            uint256 currentDay = block.timestamp / 1 days;
            DailySellRecord storage record = dailySells[from];
            
            if (record.timestamp / 1 days == currentDay) {
                record.amount += amount;
            } else {
                record.amount = amount;
                record.timestamp = block.timestamp;
            }
        }
    }
    
    // ============================ 外部函数 ============================
    
    /**
     * @dev 启用交易（仅所有者）
     */
    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "Trading already enabled");
        require(balanceOf(uniswapV2Pair) >= MIN_LIQUIDITY, "Insufficient liquidity");
        
        tradingEnabled = true;
        launchedAt = block.timestamp;
        
        emit TradingEnabled(block.timestamp);
    }
    
    /**
     * @dev 更新税率配置（仅所有者）
     * @param newConfig 新税率配置
     */
    function updateTaxConfig(TaxConfig calldata newConfig) external onlyOwner {
        require(newConfig.buyTax <= MAX_TAX_RATE, "Buy tax too high");
        require(newConfig.sellTax <= MAX_TAX_RATE, "Sell tax too high");
        require(
            newConfig.marketing + newConfig.development + newConfig.liquidity == TAX_DENOMINATOR,
            "Tax distribution must sum to 100%"
        );
        
        taxConfig = newConfig;
        emit TaxConfigUpdated(newConfig);
    }
    
    /**
     * @dev 更新交易限制（仅所有者）
     * @param newLimit 新交易限制
     */
    function updateTradeLimit(TradeLimit calldata newLimit) external onlyOwner {
        tradeLimit = newLimit;
        emit TradeLimitUpdated(newLimit);
    }
    
    /**
     * @dev 更新钱包地址（仅所有者）
     * @param marketing 新营销钱包
     * @param development 新开发钱包
     */
    function updateWallets(address marketing, address development) external onlyOwner {
        require(marketing != address(0), "Invalid marketing wallet");
        require(development != address(0), "Invalid development wallet");
        
        marketingWallet = marketing;
        developmentWallet = development;
        
        emit WalletsUpdated(marketing, development, liquidityWallet);
    }
    
    /**
     * @dev 从税收中排除/包含地址（仅所有者）
     * @param account 地址
     * @param excluded 是否排除
     */
    function excludeFromTax(address account, bool excluded) external onlyOwner {
        isExcludedFromTax[account] = excluded;
    }
    
    /**
     * @dev 从限制中排除/包含地址（仅所有者）
     * @param account 地址
     * @param excluded 是否排除
     */
    function excludeFromLimits(address account, bool excluded) external onlyOwner {
        isExcludedFromLimits[account] = excluded;
    }
    
    /**
     * @dev 手动添加流动性（仅所有者）
     * @param tokenAmount 代币数量
     */
    function addLiquidity(uint256 tokenAmount) external payable onlyOwner {
        require(msg.value > 0, "ETH amount must be > 0");
        require(tokenAmount > 0, "Token amount must be > 0");
        
        _addLiquidity(tokenAmount, msg.value);
    }
    
    /**
     * @dev 移除流动性（仅所有者）
     * @param liquidity LP代币数量
     */
    function removeLiquidity(uint256 liquidity) external onlyOwner {
        require(liquidity > 0, "Liquidity amount must be > 0");
        
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), liquidity);
        
        (uint256 tokenAmount, uint256 ethAmount) = uniswapV2Router.removeLiquidityETH(
            address(this),
            liquidity,
            0,
            0,
            owner(),
            block.timestamp
        );
        
        emit LiquidityRemoved(liquidity, tokenAmount, ethAmount);
    }
    
    /**
     * @dev 提取合约中的ETH（仅所有者）
     */
    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        
        payable(owner()).transfer(balance);
    }
    
    /**
     * @dev 提取意外发送的代币（仅所有者）
     * @param token 代币地址
     */
    function rescueToken(address token) external onlyOwner {
        require(token != address(this), "Cannot rescue own token");
        
        IERC20(token).transfer(owner(), IERC20(token).balanceOf(address(this)));
    }
    
    // ============================ 视图函数 ============================
    
    /**
     * @dev 获取地址的剩余每日卖出额度
     * @param account 地址
     * @return 剩余额度
     */
    function getRemainingDailySellLimit(address account) external view returns (uint256) {
        DailySellRecord memory record = dailySells[account];
        uint256 currentDay = block.timestamp / 1 days;
        uint256 recordDay = record.timestamp / 1 days;
        
        if (currentDay != recordDay) {
            return tradeLimit.dailySellLimit;
        }
        
        if (record.amount >= tradeLimit.dailySellLimit) {
            return 0;
        }
        
        return tradeLimit.dailySellLimit - record.amount;
    }
    
    /**
     * @dev 获取合约中的代币余额
     */
    function getContractBalance() external view returns (uint256) {
        return balanceOf(address(this));
    }
    
    /**
     * @dev 获取合约中的ETH余额
     */
    function getContractETHBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    // 接收ETH函数
    receive() external payable {}
}

// ============================ Uniswap V2 接口 ============================

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}