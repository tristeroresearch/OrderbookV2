// deploy/01_deploy_orderbook.js

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    console.log('deployer:', deployer)
    console.log('deployments:', deployments)

  
    const args = [
      // LayerZero Endpoint address
      "0x1a44076050125825900e736c501f859c50fE728c",

      // OApp Owner address
      "0x451F52446EBD4376d4a05f4267eF1a03Acf1aAf4",

      // Contract owner address
      deployer, 
      
      // LayerZero EID
      30110,            
    ];
  
    await deploy("Orderbook", {
      from: deployer,
      args: args,       // Constructor arguments
      log: true,        // Logs deployment details
      waitConfirmations: 5, // Number of confirmations to wait (adjust as needed)
    });
  };
  
  module.exports.tags = ["Orderbook"];