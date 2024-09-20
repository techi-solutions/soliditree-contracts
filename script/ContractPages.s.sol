// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {Create2} from "../src/Create2.sol";
import {ContractPages} from "../src/ContractPages.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ContractPagesDeploy is Script {
    function deploy() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the implementation contract
        ContractPages implementation = new ContractPages();

        // Prepare initialization data
        bytes memory initData = abi.encodeCall(ContractPages.initialize, (owner));

        // Prepare the creation code for the proxy
        bytes memory proxyBytecode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(address(implementation), initData));

        bytes32 salt = keccak256(abi.encodePacked("DINTERFACE_CONTRACT_PAGES_1"));

        // Deploy the proxy using Create2
        address proxyAddress = Create2(vm.envAddress("CREATE2_FACTORY_ADDRESS")).deploy(salt, proxyBytecode);

        if (proxyAddress == address(0)) {
            console.log("ContractPages proxy deployment failed");
            vm.stopBroadcast();
            return;
        }

        console.log("ContractPages implementation created at: ", address(implementation));
        console.log("ContractPages proxy created at: ", proxyAddress);

        vm.stopBroadcast();
    }

    function getContractPagesBytecode(address _owner) public pure returns (bytes memory) {
        bytes memory bytecode = type(ContractPages).creationCode;
        return abi.encodePacked(bytecode, abi.encode(_owner));
    }
}
