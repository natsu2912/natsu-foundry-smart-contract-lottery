// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig, Constants} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
//import {VRFCoordinatorV2Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
//import {LinkTokenInterface} from "@chainlink/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFCoordinatorV2_5} from "@chainlink/src/v0.8/vrf/dev/VRFCoordinatorV2_5.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script, Constants {
    function createSubscriptionUsingVrfCoordinatorAddress(
        address vrfCoordinator,
        address deployerAccount
    ) public returns (uint256 subId, address _vrfCoordinator) {
        // Create subcription
        if (block.chainid == LOCAL_ANVIL_CHAIN_ID) {
            console.log(
                "[*] Creating a new subcription for chain LOCAL_ANVIL_CHAIN_ID"
            );
            vm.startBroadcast(deployerAccount); // Only subscription owner (creator) to be DefaultSender when testing
            subId = VRFCoordinatorV2_5Mock(vrfCoordinator).createSubscription();
            vm.stopBroadcast();
        } else if (block.chainid == ETH_SEPOLIA_CHAIN_ID) {
            console.log(
                "[*] Creating a new subcription for chain ETH_SEPOLIA_CHAIN_ID"
            );
            console.log("msg.sender #1: ", msg.sender);
            console.log("Tx sent from #1: ", tx.origin);
            vm.startBroadcast(deployerAccount); // Only subscription owner (creator) to be DefaultSender when testing
            console.log("msg.sender #1: ", msg.sender);
            console.log("Tx sent from #2: ", tx.origin);
            subId = VRFCoordinatorV2_5(vrfCoordinator).createSubscription();
            vm.stopBroadcast();
        }
        console.log("Subscription ID: ", subId);
        console.log("Please update subscriptionId in HelperConfig!");
        _vrfCoordinator = vrfCoordinator;
        return (subId, _vrfCoordinator);
    }

    function createSubscriptionUsingHelperConfig()
        internal
        returns (uint256 subId, address vrfCoordinator)
    {
        // Get network config
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig
            .getActiveNetworkConfig();
        // Create subcription from network config
        (subId, vrfCoordinator) = createSubscriptionUsingVrfCoordinatorAddress(
            networkConfig.vrfCoordinator,
            networkConfig.deployerAccount
        );
        // Return
        return (subId, vrfCoordinator);
    }

    function run() external returns (uint256 subId, address vrfCoordinator) {
        return createSubscriptionUsingHelperConfig();
    }
}

contract FundSubscription is Script, Constants {
    function fundSubscription(
        address vrfCoordinator,
        uint256 subId,
        uint256 linkAmountToFund,
        address linkTokenContract,
        address deployerAccount
    ) public {
        console.log("Funding subscription: ", subId);
        console.log("Using vrfCoordinator: ", vrfCoordinator);
        console.log("On chainId: ", block.chainid);
        console.log("linkTokenContract: ", linkTokenContract);

        if (block.chainid == LOCAL_ANVIL_CHAIN_ID) {
            vm.startBroadcast(deployerAccount); // Use balance of DefaultSender to fund. Note: Can use balance //of another account
            VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(
                subId,
                linkAmountToFund
            );
            vm.stopBroadcast();
        } else {
            console.log(LinkToken(linkTokenContract).balanceOf(msg.sender));
            console.log(msg.sender);
            console.log(LinkToken(linkTokenContract).balanceOf(address(this)));
            console.log(address(this));
            vm.startBroadcast(deployerAccount);
            LinkToken(linkTokenContract).transferAndCall(
                vrfCoordinator,
                linkAmountToFund,
                abi.encode(subId)
            );
            vm.stopBroadcast();
        }
    }

    function fundSubscriptionUsingConfig(uint256 linkAmountToFund) internal {
        // Get network config
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig
            .getActiveNetworkConfig();
        // Create subcription if we don't have one
        CreateSubscription subscriptionCreator;
        if (networkConfig.subscriptionId == 0) {
            subscriptionCreator = new CreateSubscription();
            (
                networkConfig.subscriptionId, // Set subscriptionId after creation
                networkConfig.vrfCoordinator // Set vrfCoordinator after creation
            ) = subscriptionCreator
                .createSubscriptionUsingVrfCoordinatorAddress(
                    networkConfig.vrfCoordinator,
                    networkConfig.deployerAccount
                );
            console.log(
                "New SubId Created! ",
                networkConfig.subscriptionId,
                "VRF Address: ",
                networkConfig.vrfCoordinator
            );
        }
        // Fund subcription
        fundSubscription(
            networkConfig.vrfCoordinator,
            networkConfig.subscriptionId,
            linkAmountToFund,
            networkConfig.linkTokenContract,
            networkConfig.deployerAccount
        );
    }

    function run() external {
        uint256 LINK_AMOUNT_TO_FUND = 100 ether; // 100 LINK
        fundSubscriptionUsingConfig(LINK_AMOUNT_TO_FUND);
    }
}

contract AddConsumer is Script {
    function addConsumer(
        address vrfCoordinator,
        uint256 subId,
        address consumer,
        address deployerAccount
    ) public {
        console.log("Adding consumer contract: ", consumer);
        console.log("Using VRFCoordinator: ", vrfCoordinator);
        console.log("On chain id: ", block.chainid);

        vm.startBroadcast(deployerAccount); // Only subscription owner (creator) can add consumer
        VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(subId, consumer);
        vm.stopBroadcast();
    }

    function addConsumerUsingConfig(
        address raffle,
        HelperConfig helperConfig
    ) internal {
        // Get network config
        HelperConfig.NetworkConfig memory networkConfig = helperConfig
            .getActiveNetworkConfig();
        // Add Raffle contract as Consumer
        addConsumer(
            networkConfig.vrfCoordinator,
            networkConfig.subscriptionId,
            raffle,
            networkConfig.deployerAccount
        );
    }

    function run(address raffle, HelperConfig helperConfig) external {
        //address raffle = DevOpsTools.get_most_recent_deployment(
        //    "Raffle",
        //    block.chainid
        //);
        addConsumerUsingConfig(raffle, helperConfig);
    }
}
