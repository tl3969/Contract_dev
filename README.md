## 完整部署和使用指南

1. 环境设置
    bash
    # 1. 安装Foundry
    curl -L https://foundry.paradigm.xyz | bash
    foundryup

    # 2. 创建项目
    forge init meme-token
    cd meme-token

    # 3. 安装依赖
    forge install OpenZeppelin/openzeppelin-contracts --no-commit

    # 4. 创建目录结构
    mkdir -p src test script
## 2. 环境变量配置
    创建 .env 文件：

    bash
    # 网络配置
    SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
    MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY

    # 私钥（从MetaMask导出或使用测试私钥）
    PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
    MAINNET_PRIVATE_KEY=your_mainnet_private_key

    # 钱包地址
    MARKETING_WALLET=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
    DEVELOPMENT_WALLET=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC

    # 区块浏览器API
    ETHERSCAN_API_KEY=your_etherscan_api_key

## 3. 部署到测试网
    bash
    # 1. 编译合约
    forge build

    # 2. 运行测试
    forge test -vvv
    forge test --gas-report

    # 3. 生成代码覆盖率报告
    forge coverage --report lcov && genhtml lcov.info -o coverage

    # 4. 部署到Sepolia测试网
    forge script script/Deploy.s.sol:DeployMemeToken \
        --rpc-url $SEPOLIA_RPC_URL \
        --private-key $PRIVATE_KEY \
        --broadcast \
        --verify \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        -vvvv

    # 5. 配置代币（添加流动性、启用交易）
    forge script script/Deploy.s.sol:ConfigureToken \
        --rpc-url $SEPOLIA_RPC_URL \
        --private-key $PRIVATE_KEY \
        --broadcast \
        -vvvv
## 4. 测试命令和报告
    运行完整测试套件：
    bash
    # 运行所有测试
    forge test -vvv

    # 运行特定测试
    forge test --match-test test_BuyTax -vvv

    # 运行Gas报告
    forge test --gas-report

    # 运行Fuzz测试
    forge test --match-test testFuzz --fuzz-runs 1000
    生成Gas报告示例输出：
    text
    | Function Name           | min     | avg    | median | max    | # calls |
    |-------------------------|---------|--------|--------|--------|---------|
    | transfer                | 23015   | 51234  | 51234  | 79453  | 100     |
    | approve                 | 24407   | 24407  | 24407  | 24407  | 50      |
    | transferFrom            | 35678   | 47891  | 47891  | 60104  | 50      |
    | addLiquidity            | 150234  | 150234 | 150234 | 150234 | 10      |
    | enableTrading           | 28912   | 28912  | 28912  | 28912  | 5       |
    生成代码覆盖率报告：
    bash
    # 安装覆盖率工具
    forge coverage

    # 生成HTML报告
    forge coverage --report html

    # 查看覆盖率摘要
    forge coverage --report summary
    示例覆盖率报告：

    text
    File                    | % Stmts   | % Branch  | % Funcs   | % Lines   |
    ------------------------|-----------|-----------|-----------|-----------|
    src/MemeToken.sol       | 98.23%    | 95.67%    | 100%      | 98.23%    |
    test/MemeTokenTest.t.sol| 100%      | 100%      | 100%      | 100%      |
    Total                   | 98.67%    | 96.45%    | 100%      | 98.67%    |

## 5. 安全审计清单
    # 1. 运行Slither静态分析
    slither . --exclude-informational --exclude-low

    # 2. 运行Mythril安全分析
    myth analyze src/MemeToken.sol

    # 3. 手动安全检查
    # - [ ] 验证所有数学运算无溢出
    # - [ ] 验证权限控制正确
    # - [ ] 验证税收计算准确
    # - [ ] 验证交易限制有效
    # - [ ] 验证流动性功能安全

项目结构

        Contract_dev/
    ├── src/
    │   └── MemeToken.sol          # 主合约
    ├── test/
    │   └── MemeTokenTest.t.sol    # Foundry测试
    ├── script/
    │   └── Deploy.s.sol           # 部署脚本
    ├── .env                       # 环境变量
    ├── foundry.toml              # Foundry配置
    ├── README.md                 # 项目文档
    └── coverage/                 # 覆盖率报告