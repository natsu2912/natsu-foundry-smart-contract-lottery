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
    uint256 internal STARTING_BALANCE = 100 ether;
    uint256 internal entranceFee;
    uint256 internal interval;
    address internal vrfCoordinator;
    bytes32 internal gasLane;
    uint64 internal subscriptionId;
    uint32 internal callbackGasLimit;

    function setUp() external {
        // Set up the test environment
        DeployRaffle raffleDeployer = new DeployRaffle();
        (raffle, helperConfig) = raffleDeployer.deployContract();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig
            .getActiveNetworkConfig();
        entranceFee = networkConfig.entranceFee;
        interval = networkConfig.interval;
        vrfCoordinator = networkConfig.vrfCoordinator;
        gasLane = networkConfig.gasLane;
        subscriptionId = networkConfig.subscriptionId;
        callbackGasLimit = networkConfig.callbackGasLimit;

        // Give players some ether
        vm.deal(PLAYER_ALICE, STARTING_BALANCE);
        vm.deal(PLAYER_BOB, STARTING_BALANCE);
    }

    function testRaffleInitializsInOpenState() external view {
        // Assert
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleEntranceFeeIsCorrect() external view {
        // Assert
        assert(raffle.getEntranceFee() == entranceFee);
    }

    function testEnterRaffleRevertWhenDontPayEnoughToEnterRaffle() external {
        // Arragnge
        vm.prank(PLAYER_ALICE);
        // Act + Assert #1
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__NotEnoughEthSent.selector,
                entranceFee - 1 wei,
                entranceFee
            )
        );
        raffle.enterRaffle{value: entranceFee - 1 wei}();
        // Assert #2
        assert(address(raffle).balance == 0);
        assert(PLAYER_ALICE.balance == STARTING_BALANCE);
        assert(raffle.getNumberOfPlayers() == 0);
    }

    // Todo
    //function testEnterRaffleRevertWhenRaffleIsNotOpen() external {
    //    vm.prank(PLAYER_ALICE);
    //    raffle.enterRaffle{value: entranceFee}();
    //}

    function testEnterRafflePlayersEnter() external {
        // Arrage
        vm.prank(PLAYER_ALICE);
        // Act + Assert #1
        vm.expectEmit(true, false, false, false, address(raffle));
        emit Raffle.EnteredRaffle(PLAYER_ALICE);
        raffle.enterRaffle{value: entranceFee}();
        // Assert #2
        assert(address(raffle).balance == entranceFee);
        assert(PLAYER_ALICE.balance == STARTING_BALANCE - entranceFee);
        assert(raffle.getNumberOfPlayers() == 1);
        assert(raffle.getPlayer(0) == PLAYER_ALICE);
    }

    function testPerformUpkeepRevertWhenIntervalIsNotPassed() external {
        // Arrage
        vm.prank(PLAYER_ALICE);
        // Act + Assert
        raffle.enterRaffle{value: entranceFee}();
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Automation__UpkeepNotNeeded.selector,
                false,
                entranceFee,
                1,
                Raffle.RaffleState.OPEN
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertWhenContractNotHasBalanceAndNotHasPlayer()
        external
    {
        // Arrange
        vm.warp(raffle.getLastTimeStamp() + interval);
        // Act + Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Automation__UpkeepNotNeeded.selector,
                true,
                0,
                0,
                Raffle.RaffleState.OPEN
            )
        );
        raffle.performUpkeep("");
    }

    // Todo
    //function testPerformUpkeepRevertWhenRaffleIsNotOpen() external {
    //    vm.prank(PLAYER_ALICE);
    //    raffle.enterRaffle{value: entranceFee}();
    //    vm.warp(raffle.getLastTimeStamp() + interval);
    //
    //    // 1st performUpkeep should be successful
    //    raffle.performUpkeep("");
    //
    //    // 2nd performUpkeep should revert
    //    vm.expectRevert(
    //        abi.encodeWithSelector(
    //            Raffle.Automation__UpkeepNotNeeded.selector,
    //            true,
    //            entranceFee,
    //            1,
    //            Raffle.RaffleState.CALCULATING
    //        )
    //    );
    //    raffle.performUpkeep("");
    //}

    function testFallbackWhenPlayerSendEth() external {
        // Arrange
        vm.prank(PLAYER_ALICE);
        // Act
        (bool success, ) = address(raffle).call{value: entranceFee}(
            hex"abcdef"
        );
        // Assert
        assert(success);
        assert(address(raffle).balance == entranceFee);
        assert(PLAYER_ALICE.balance == STARTING_BALANCE - entranceFee);
        assert(raffle.getNumberOfPlayers() == 1);
        assert(raffle.getPlayer(0) == PLAYER_ALICE);
    }

    function testFallbackWhenPlayerDontSendEth() external {
        // Arrange
        vm.prank(PLAYER_ALICE);
        // Act + Assert #1
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__NotEnoughEthSent.selector,
                entranceFee - 1 wei,
                entranceFee
            )
        );
        (bool success, ) = address(raffle).call{value: entranceFee - 1234 wei}(
            hex"abcdef"
        ); // This call should revert and sucess should be false
        // Assert #2
        assert(success == false);
        assert(address(raffle).balance == 0);
        assert(PLAYER_ALICE.balance == STARTING_BALANCE);
        assert(raffle.getNumberOfPlayers() == 0);
    }

    function testReceiveWhenPlayerSendEth() external {
        // Arrange
        vm.prank(PLAYER_ALICE);
        // Act
        (bool success, ) = address(raffle).call{value: entranceFee}("");
        // Assert
        assert(success);
        assert(address(raffle).balance == entranceFee);
        assert(PLAYER_ALICE.balance == STARTING_BALANCE - entranceFee);
        assert(raffle.getNumberOfPlayers() == 1);
        assert(raffle.getPlayer(0) == PLAYER_ALICE);
    }

    function testReceiveWhenPlayerDontSendEth() external {
        // Arrage
        vm.prank(PLAYER_ALICE);
        // Act + Assert #1
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__NotEnoughEthSent.selector,
                entranceFee - 1 wei,
                entranceFee
            )
        );
        (bool success, ) = address(raffle).call{value: entranceFee - 1234 wei}(
            ""
        ); // This call should revert and sucess should be false
        // Assert #2
        assert(success == false);
        assert(address(raffle).balance == 0);
        assert(PLAYER_ALICE.balance == STARTING_BALANCE);
        assert(raffle.getNumberOfPlayers() == 0);
    }

    /*//////////////////////////////////////////////////////////////
                              ENTER RAFFLE
    //////////////////////////////////////////////////////////////*/
}
