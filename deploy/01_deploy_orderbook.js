// deploy/01_deploy_orderbook.js

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    console.log('deployer:', deployer)
    console.log('deployments:', deployments)

  
    const args = [
      "0x1a44076050125825900e736c501f859c50fE728c", // Replace with actual endpoint address if needed
      deployer,                      // Owner address
      30110,            // Replace with actual LayerZero EID if needed
    ];
  
    await deploy("Orderbook", {
      from: deployer,
      args: args,       // Constructor arguments
      log: true,        // Logs deployment details
      waitConfirmations: 5, // Number of confirmations to wait (adjust as needed)
    });
  };
  
  module.exports.tags = ["Orderbook"];