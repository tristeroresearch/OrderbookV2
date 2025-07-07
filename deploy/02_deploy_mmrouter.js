// deploy/02_deploy_mmrouter.js

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, get } = deployments;
    const { deployer } = await getNamedAccounts();
    
    console.log('deployer:', deployer);
    
    // Get the deployed Orderbook contract address
    const orderbook = await get("Orderbook");
    console.log('Orderbook address:', orderbook.address);
  
    const args = [
      orderbook.address,  // TradeInterface _ob (the Orderbook contract)
    ];
  
    await deploy("MMRouter", {
      from: deployer,
      args: args,
      log: true,
      waitConfirmations: 5,
    });
  };
  
  module.exports.tags = ["MMRouter"];
  module.exports.dependencies = ["Orderbook"]; // Deploy after Orderbook 