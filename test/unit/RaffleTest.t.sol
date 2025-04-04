// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract RaffleTest is Test {
    Raffle internal raffle;
    HelperConfig internal helperConfig;

    address internal PLAYER_ALICE = makeAddr("PlayerAlice");
    address internal PLAYER_BOB = makeAddr("PlayerBob");

    function setUp() external {
        DeployRaffle raffleDeployer = new DeployRaffle();
        (raffle, helperConfig) = raffleDeployer.deployContract();
    }
}
