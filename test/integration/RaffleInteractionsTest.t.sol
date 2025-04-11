// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interactions.s.sol";
import {Raffle} from "src/Raffle.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";

import {HelperConfig} from "script/HelperConfig.s.sol";

contract RaffleInteractionsTest is Test {
    function setUp() external {}

    function testCreateSubscription() external {
        // Act
        CreateSubscription subscriptionCreator = new CreateSubscription();
        (uint256 subId, address vrfCoordinator) = subscriptionCreator.run();

        // Assert
        console.log("Subscription ID: ", subId);
        console.log("VRF Coordinator Address: ", vrfCoordinator);
        assert(subId > 0);
        assert(vrfCoordinator != address(0));
    }

    function testFundSubscription() external {
        // Ac
        FundSubscription subscriptionFunder = new FundSubscription();
        subscriptionFunder.run();
    }

    function testAddConsumer() external {
        // Arrage
        DeployRaffle deployRaffle = new DeployRaffle();
        (Raffle raffle, HelperConfig helperConfig) = deployRaffle.run();
        // Act
        AddConsumer consumerAdder = new AddConsumer();
        consumerAdder.run(address(raffle), helperConfig);

        // Assert
        // Add assertions as needed
    }
}
