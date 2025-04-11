/// Layout of the contract file:
// version
// imports
// errors
// interfaces, libraries, contract

/// Layout of Contract:
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

/// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
//import {VRFCoordinatorV2Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

abstract contract Constants {
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_ANVIL_CHAIN_ID = 31337;
    uint256 public constant MAINNET_CHAIN_ID = 1;
}

contract HelperConfig is Script, Constants {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint256 subscriptionId;
        uint32 callbackGasLimit;
        address linkTokenContract;
        address deployerAccount;
    }

    mapping(uint256 => NetworkConfig) private s_networkConfigs;
    NetworkConfig private s_activeNetworkConfig;

    constructor() {
        s_networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
        s_activeNetworkConfig = getConfig();
    }

    function getActiveNetworkConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        return s_activeNetworkConfig;
    }

    function setActiveNetworkConfig(NetworkConfig memory networkConfig) public {
        s_activeNetworkConfig = networkConfig;
    }

    function setSubIdForActiveNetworkConfig(uint256 subId) public {
        s_activeNetworkConfig.subscriptionId = subId;
    }

    function setVrfCoordinatorForActiveNetworkConfig(
        address vrfCoordinator
    ) public {
        s_activeNetworkConfig.vrfCoordinator = vrfCoordinator;
    }

    function getSepoliaEthConfig()
        internal
        view
        returns (NetworkConfig memory)
    {
        return
            NetworkConfig({
                entranceFee: 0.01 ether, // 1e16
                interval: 30, // 30 seconds
                vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
                gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
                //subscriptionId: 70114033652876626055761777853900633248033356250955478684534941029272930067759, // wrong subId, created when testing
                //subscriptionId: 112508787565041413133707041134491316795283384790279550650135492764536720496235, // correct subId, view on website
                subscriptionId: 0, // 0 -> Create a new subscription
                callbackGasLimit: 500000,
                linkTokenContract: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
                deployerAccount: vm.envAddress("SEPOLIA_SENDER_ADDRESS")
            });
    }

    function getOrCreateAnvilEthConfig()
        internal
        returns (NetworkConfig memory)
    {
        if (s_activeNetworkConfig.vrfCoordinator != address(0)) {
            return s_activeNetworkConfig; // Use existing config if available
        } else {
            // VRF Mocks Constant Values
            uint96 MOCK_BASE_FEE = 0.25 ether; // 0.25 LINK per request;
            uint96 MOCK_GAS_PRICE_LINK = 1e9; // 0.000000001 LINK per gas
            int256 MOCK_WEI_PER_UNIT_LINK = 4e15; // 1 LINK = 4e15 wei = 0.004 ether;

            // Create a new VRFCoordinator Mock instance and a new LinkToken instance
            vm.startBroadcast();
            VRFCoordinatorV2_5Mock mockVrfCoordinator = new VRFCoordinatorV2_5Mock(
                    MOCK_BASE_FEE,
                    MOCK_GAS_PRICE_LINK,
                    MOCK_WEI_PER_UNIT_LINK
                );
            LinkToken linkToken = new LinkToken();
            vm.stopBroadcast();
            // Return a new NetworkConfig instance
            return
                NetworkConfig({
                    entranceFee: 0.01 ether, // 1e16
                    interval: 30, // 30 seconds
                    vrfCoordinator: address(mockVrfCoordinator), // Local network doesn't have a VRF coordinator
                    gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae, // gasLane value doesn't matter in Local Anvil network
                    subscriptionId: 0, // 0 -> Create a new subscription
                    callbackGasLimit: 500000,
                    linkTokenContract: address(linkToken),
                    deployerAccount: vm.envAddress("LOCAL_SENDER_ADDRESS")
                });
        }
    }

    function getConfigByChainId(
        uint256 chainId
    ) internal returns (NetworkConfig memory) {
        if (s_networkConfigs[chainId].vrfCoordinator != address(0)) {
            return s_networkConfigs[chainId];
        } else if (chainId == LOCAL_ANVIL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getConfig() internal returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }
}
