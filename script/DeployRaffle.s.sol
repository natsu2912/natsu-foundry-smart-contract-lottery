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

import {Script, console} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

//import {VRFCoordinatorV2Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

contract DeployRaffle is Script {
    /**
     * @dev external functions
     */
    function run() external {
        deployContract();
    }

    /**
     * @dev public functions
     */
    function deployContract() public returns (Raffle, HelperConfig) {
        // Get or create network configuration
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
                    address(networkConfig.vrfCoordinator),
                    networkConfig.deployerAccount
                );
        }

        // Fund subscription if LINK < 5 ether
        uint256 MINIMUM_LINK_AMOUNT = 300 ether; // 300 LINK
        uint256 LINK_AMOUNT_TO_FUND = 300 ether; // 300 LINK
        (uint256 current_subscription_balance, , , , ) = VRFCoordinatorV2_5Mock(
            networkConfig.vrfCoordinator
        ).getSubscription(networkConfig.subscriptionId);
        if (current_subscription_balance < MINIMUM_LINK_AMOUNT) {
            FundSubscription subscriptionFunder = new FundSubscription();
            subscriptionFunder.fundSubscription(
                networkConfig.vrfCoordinator,
                networkConfig.subscriptionId,
                LINK_AMOUNT_TO_FUND,
                networkConfig.linkTokenContract,
                networkConfig.deployerAccount
            );
        }

        // Deploy the Raffle contract
        vm.startBroadcast();
        Raffle raffle = new Raffle(
            networkConfig.entranceFee,
            networkConfig.interval,
            networkConfig.vrfCoordinator,
            networkConfig.gasLane,
            networkConfig.subscriptionId,
            networkConfig.callbackGasLimit
        );
        vm.stopBroadcast();

        // Add Raffle contract as consumer
        AddConsumer consumerAdder = new AddConsumer();
        // Don't need to broadcast here...
        consumerAdder.addConsumer(
            networkConfig.vrfCoordinator,
            networkConfig.subscriptionId,
            address(raffle),
            networkConfig.deployerAccount
        );

        // Return
        return (raffle, helperConfig);
    }
}
