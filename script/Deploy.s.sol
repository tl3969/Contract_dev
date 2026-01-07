// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MemeToken.sol";

/**
 * @title MemeToken部署脚本
 * @notice 用于在不同网络部署MemeToken合约
 */
contract DeployMemeToken is Script {
    // 网络配置
    struct NetworkConfig {
        address router;
        uint256 deployerPrivateKey;
    }
    
    // 默认配置（测试网）
    NetworkConfig public sepoliaConfig = NetworkConfig({
        router: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, // Uniswap V2 Router
        deployerPrivateKey: vm.envUint("PRIVATE_KEY")
    });
    
    // 主网配置
    NetworkConfig public mainnetConfig = NetworkConfig({
        router: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,
        deployerPrivateKey: vm.envUint("MAINNET_PRIVATE_KEY")
    });
    
    function run() external {
        // 根据网络选择配置
        NetworkConfig memory config;
        
        if (block.chainid == 1) { // Ethereum Mainnet
            config = mainnetConfig;
            console.log("Deploying to Ethereum Mainnet");
        } else if (block.chainid == 11155111) { // Sepolia
            config = sepoliaConfig;
            console.log("Deploying to Sepolia Testnet");
        } else {
            revert("Unsupported network");
        }
        
        // 从环境变量获取钱包地址
        address marketingWallet = vm.envAddress("MARKETING_WALLET");
        address developmentWallet = vm.envAddress("DEVELOPMENT_WALLET");
        
        require(marketingWallet != address(0), "Marketing wallet not set");
        require(developmentWallet != address(0), "Development wallet not set");
        
        // 部署参数
        string memory tokenName = "Meme Coin";
        string memory tokenSymbol = "MEME";
        uint256 totalSupply = 1_000_000_000 * 10**18; // 10亿代币
        
        console.log("Deployment Parameters:");
        console.log("Token Name:", tokenName);
        console.log("Token Symbol:", tokenSymbol);
        console.log("Total Supply:", totalSupply / 10**18, "tokens");
        console.log("Marketing Wallet:", marketingWallet);
        console.log("Development Wallet:", developmentWallet);
        console.log("Uniswap Router:", config.router);
        
        // 开始广播交易
        vm.startBroadcast(config.deployerPrivateKey);
        
        // 部署合约
        MemeToken memeToken = new MemeToken(
            tokenName,
            tokenSymbol,
            totalSupply,
            config.router,
            marketingWallet,
            developmentWallet
        );
        
        vm.stopBroadcast();
        
        // 输出部署信息
        console.log("\n=== Deployment Successful ===");
        console.log("Contract Address:", address(memeToken));
        console.log("Owner:", memeToken.owner());
        console.log("Uniswap Pair:", memeToken.uniswapV2Pair());
        console.log("\nNext steps:");
        console.log("1. Add initial liquidity");
        console.log("2. Enable trading");
        console.log("3. Verify contract on block explorer");
    }
}

// 部署后配置脚本
contract ConfigureToken is Script {
    function run() external {
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        require(tokenAddress != address(0), "Token address not set");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        MemeToken token = MemeToken(tokenAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. 添加初始流动性
        console.log("Adding initial liquidity...");
        uint256 tokenAmount = 500_000_000 * 10**18; // 5亿代币
        uint256 ethAmount = 10 ether;
        
        // 批准代币
        token.approve(address(token), tokenAmount);
        
        // 添加流动性（需要先发送ETH到脚本）
        token.addLiquidity{value: ethAmount}(tokenAmount);
        
        console.log("Liquidity added:", tokenAmount / 10**18, "tokens +", ethAmount / 10**18, "ETH");
        
        // 2. 启用交易
        console.log("Enabling trading...");
        token.enableTrading();
        
        console.log("Trading enabled at block:", token.launchedAt());
        
        // 3. 设置交易限制
        console.log("Setting trade limits...");
        
        MemeToken.TradeLimit memory limits = MemeToken.TradeLimit({
            maxTxAmount: token.totalSupply() / 100,      // 1%
            maxWalletAmount: token.totalSupply() / 50,   // 2%
            dailySellLimit: token.totalSupply() / 200,   // 0.5%
            antiWhaleEnabled: true
        });
        
        token.updateTradeLimit(limits);
        
        console.log("Trade limits configured");
        
        vm.stopBroadcast();
        
        console.log("\n=== Token Configuration Complete ===");
        console.log("Token is now live and tradable!");
    }
}