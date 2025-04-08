// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {CreateSubscription} from "script/Interactions.s.sol";
import {console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
//import {VRFCoordinatorV2Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";
import {SubscriptionAPI} from "@chainlink/src/v0.8/vrf/dev/SubscriptionAPI.sol";

contract RaffleTest is Test {
    Raffle internal s_raffle;
    HelperConfig internal s_helperConfig;
    address private PLAYER_ALICE = makeAddr("PlayerAlice");
    address private PLAYER_BOB = makeAddr("PlayerBob");
    uint256 private STARTING_BALANCE = 100 ether;
    uint256 private s_entranceFee;
    uint256 private s_interval;
    address private s_vrfCoordinator;
    bytes32 private s_gasLane;
    uint256 private s_subscriptionId;
    uint32 private s_callbackGasLimit;
    address private s_linkTokenContract;
    address private s_deployerAccount;

    function setUp() external {
        // Deploy the Raffle contract
        DeployRaffle raffleDeployer = new DeployRaffle();
        (s_raffle, s_helperConfig) = raffleDeployer.deployContract();

        // Get network configuration
        HelperConfig.NetworkConfig memory networkConfig = s_helperConfig
            .getActiveNetworkConfig();
        s_entranceFee = networkConfig.entranceFee;
        s_interval = networkConfig.interval;
        s_vrfCoordinator = networkConfig.vrfCoordinator;
        s_gasLane = networkConfig.gasLane;
        s_subscriptionId = networkConfig.subscriptionId;
        s_callbackGasLimit = networkConfig.callbackGasLimit;
        s_linkTokenContract = networkConfig.linkTokenContract;
        s_deployerAccount = networkConfig.deployerAccount;

        // Give players some ether
        vm.deal(PLAYER_ALICE, STARTING_BALANCE);
        vm.deal(PLAYER_BOB, STARTING_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                              SIMPLE TEST
    //////////////////////////////////////////////////////////////*/

    function testRaffleInitializesInOpenState() external view {
        // Assert
        assert(s_raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleEntranceFeeIsCorrect() external view {
        // Assert
        assert(s_raffle.getEntranceFee() == s_entranceFee);
    }

    /*//////////////////////////////////////////////////////////////
                                MODIFIER
    //////////////////////////////////////////////////////////////*/

    modifier aliceEnterRaffleAndTimeHasPassed() {
        vm.prank(PLAYER_ALICE);
        s_raffle.enterRaffle{value: s_entranceFee}();
        vm.warp(s_raffle.getLastTimeStamp() + s_interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            // 31337 = LOCAl_ANVIL_CHAIN_ID
            return;
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              ENTER RAFFLE
    //////////////////////////////////////////////////////////////*/

    function testEnterRaffleRevertWhenDontPayEnoughToEnterRaffle() external {
        // Arrange
        uint256 startingRaffleBalance = address(s_raffle).balance;
        vm.prank(PLAYER_ALICE);
        // Act + Assert #1
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__NotEnoughEthSent.selector,
                s_entranceFee - 1 wei,
                s_entranceFee
            )
        );
        s_raffle.enterRaffle{value: s_entranceFee - 1 wei}();
        // Assert #2
        assert(address(s_raffle).balance == startingRaffleBalance);
        assert(PLAYER_ALICE.balance == STARTING_BALANCE);
        assert(s_raffle.getNumberOfPlayers() == 0);
    }

    function testEnterRaffleRevertWhenRaffleIsNotOpen()
        external
        aliceEnterRaffleAndTimeHasPassed
    {
        // performUpkeep should be successful
        s_raffle.performUpkeep("");

        // Act + Assert
        // enterRaffle should revert because the raffle is in CALCULATING state
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__RaffleNotOpen.selector)
        );
        vm.prank(PLAYER_BOB);
        s_raffle.enterRaffle{value: s_entranceFee}();
    }

    function testEnterRaffleSuccessful() external {
        // Arrage
        uint256 startingRaffleBalance = address(s_raffle).balance;
        vm.prank(PLAYER_ALICE);
        // Act + Assert #1
        vm.expectEmit(true, false, false, false, address(s_raffle));
        emit Raffle.EnteredRaffle(PLAYER_ALICE);
        s_raffle.enterRaffle{value: s_entranceFee}();
        // Assert #2

        assert(
            address(s_raffle).balance == startingRaffleBalance + s_entranceFee
        );
        assert(PLAYER_ALICE.balance == STARTING_BALANCE - s_entranceFee);
        assert(s_raffle.getNumberOfPlayers() == 1);
        assert(s_raffle.getPlayer(0) == PLAYER_ALICE);
    }

    /*//////////////////////////////////////////////////////////////
                              CHECK UPKEEP
    //////////////////////////////////////////////////////////////*/

    function testCheckUpkeepReturnFalseWhenIntervalIsNotPassed() external {
        // Arrage
        vm.prank(PLAYER_ALICE);
        s_raffle.enterRaffle{value: s_entranceFee}();
        // Act
        (bool upkeepNeeded, bytes memory performData) = s_raffle.checkUpkeep(
            bytes("")
        );
        // Assert
        assert(upkeepNeeded == false);
        assert(abi.decode(performData, (bool)) == false);
    }

    function testCheckUpkeepReturnFalseWhenContractNotHasBalanceAndNotHasPlayer()
        external
    {
        // Arrange
        vm.warp(s_raffle.getLastTimeStamp() + s_interval);
        vm.roll(block.number + 1);
        // Act
        (bool upkeepNeeded, bytes memory performData) = s_raffle.checkUpkeep(
            bytes("")
        );
        // Assert
        assert(upkeepNeeded == false);
        assert(abi.decode(performData, (bool)) == true);
    }

    function testCheckUpkeepReturnFalseWhenRaffleIsNotOpen()
        external
        aliceEnterRaffleAndTimeHasPassed
    {
        // 1st performUpkeep should be successful
        s_raffle.performUpkeep("");

        // Act
        // 2nd performUpkeep should revert because the raffle is in CALCULATING state
        (bool upkeepNeeded, ) = s_raffle.checkUpkeep(bytes(""));

        // Assert
        assert(upkeepNeeded == false);
        assert(s_raffle.getRaffleState() != Raffle.RaffleState.OPEN);
    }

    function testcheckUpkeepReturnTrue()
        external
        aliceEnterRaffleAndTimeHasPassed
    {
        // Act
        (bool upkeepNeeded, ) = s_raffle.checkUpkeep(bytes(""));

        // Assert
        assert(upkeepNeeded == true);
    }

    /*//////////////////////////////////////////////////////////////
                             PERFORM UPKEEP
    //////////////////////////////////////////////////////////////*/

    function testPerformUpkeepRevertWhenIntervalIsNotPassed() external {
        // Arrage
        uint256 startingRaffleBalance = address(s_raffle).balance;
        vm.prank(PLAYER_ALICE);
        s_raffle.enterRaffle{value: s_entranceFee}();
        // Act + Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Automation__UpkeepNotNeeded.selector,
                false,
                startingRaffleBalance + s_entranceFee,
                1,
                Raffle.RaffleState.OPEN
            )
        );
        s_raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertWhenContractNotHasBalanceAndNotHasPlayer()
        external
    {
        // Arrange
        uint256 startingRaffleBalance = address(s_raffle).balance;
        vm.warp(s_raffle.getLastTimeStamp() + s_interval);
        vm.roll(block.number + 1);
        // Act + Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Automation__UpkeepNotNeeded.selector,
                true, // interval has passed
                startingRaffleBalance, // contract balance
                0, // number of players
                Raffle.RaffleState.OPEN
            )
        );
        s_raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertWhenRaffleIsNotOpen()
        external
        aliceEnterRaffleAndTimeHasPassed
    {
        // Arrange
        uint256 startingRaffleBalance = address(s_raffle).balance;
        // 1st performUpkeep should be successful
        s_raffle.performUpkeep("");

        // Act + Assert
        // 2nd performUpkeep should revert because the raffle is in CALCULATING state
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Automation__UpkeepNotNeeded.selector,
                true, // interval has passed
                startingRaffleBalance, // contract balance
                1, // number of players
                Raffle.RaffleState.CALCULATING
            )
        );
        s_raffle.performUpkeep("");
    }

    function testPerformUpkeepSuccessfulExpectEmitWhenWeKnowRequestId()
        external
        aliceEnterRaffleAndTimeHasPassed
    {
        // Act + Assert #1
        /*
        // We know requestId is 1 (Only when testing with local Anvil Chain)
        vm.expectEmit(true, false, false, false, address(raffle));
        emit Raffle.WinnerPickRequestSent(1); 
        */
        vm.expectEmit(false, false, false, false, address(s_raffle));
        emit Raffle.WinnerPickRequestSent(0); // requestId is not important because we do not check it
        s_raffle.performUpkeep(""); // This call will emit requestId with "emit WinnerPickRequestSent(requestId);"

        // Assert #2 // Temporary assertion, need to learn how to skip to when the Raffle finish the calculation -> Done in function "testFulfillRandomWordsSuccessfulWhenPerformHasBeenCalledAndThenPicksAWinnerAndSendsMoney"
        assert(s_raffle.getRaffleState() == Raffle.RaffleState.CALCULATING);

        ////// Test -> Cannot convert raffle state to OPEN -> Must find out how to "confirm" 3 times (3 times = REQUEST_CONFIRMATIONS)
        //// Arrange 2 ->
        //vm.warp(raffle.getLastTimeStamp() + interval * 10 + 1);
        //vm.roll(block.number + 10);
        //
        //// Assert 2
        //assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testPerformUpkeepSuccessfulWhenWeDontKnowRequestId()
        external
        aliceEnterRaffleAndTimeHasPassed
    {
        // Act
        vm.recordLogs();
        s_raffle.performUpkeep(""); // This call will emit requestId with "emit WinnerPickRequestSent(requestId);"
        Vm.Log[] memory logEntries = vm.getRecordedLogs();
        // logEntries[0] is log of function "requestRandomWords" at line "emit RandomWordsRequested(...);" in file "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol" -> logEntries[1] is log of this "emit WinnerPickRequestSent(requestId);"
        // logEntries[1].topics[0] is keccak256("WinnerPickRequestSent(uint256)") -> logEntries[1].topics[1] is requestId
        bytes32 requestId = logEntries[1].topics[1];

        // Assert
        assert(uint256(requestId) > 0);
        assert(s_raffle.getRaffleState() == Raffle.RaffleState.CALCULATING);
    }

    /*//////////////////////////////////////////////////////////////
                                FALLBACK
    //////////////////////////////////////////////////////////////*/

    function testFallbackWhenPlayerSendEth() external {
        // Arrange
        uint256 startingRaffleBalance = address(s_raffle).balance;
        vm.prank(PLAYER_ALICE);
        // Act
        (bool success, ) = address(s_raffle).call{value: s_entranceFee}(
            hex"abcdef"
        );
        // Assert
        assert(success);
        assert(
            address(s_raffle).balance == startingRaffleBalance + s_entranceFee
        );
        assert(PLAYER_ALICE.balance == STARTING_BALANCE - s_entranceFee);
        assert(s_raffle.getNumberOfPlayers() == 1);
        assert(s_raffle.getPlayer(0) == PLAYER_ALICE);
    }

    function testFallbackWhenPlayerDontSendEth() external {
        // Arrange
        uint256 startingRaffleBalance = address(s_raffle).balance;
        vm.prank(PLAYER_ALICE);
        // Act + Assert #1
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__NotEnoughEthSent.selector,
                s_entranceFee - 1 wei,
                s_entranceFee
            )
        );
        (bool success, ) = address(s_raffle).call{
            value: s_entranceFee - 1234 wei
        }(hex"abcdef"); // This call should revert and sucess should be false
        // Assert #2
        assert(success == false);
        assert(address(s_raffle).balance == startingRaffleBalance);
        assert(PLAYER_ALICE.balance == STARTING_BALANCE);
        assert(s_raffle.getNumberOfPlayers() == 0);
    }

    /*//////////////////////////////////////////////////////////////
                                RECEIVE
    //////////////////////////////////////////////////////////////*/

    function testReceiveWhenPlayerSendEth() external {
        // Arrange
        uint256 startingRaffleBalance = address(s_raffle).balance;
        vm.prank(PLAYER_ALICE);
        // Act
        (bool success, ) = address(s_raffle).call{value: s_entranceFee}("");
        // Assert
        assert(success);
        assert(
            address(s_raffle).balance == startingRaffleBalance + s_entranceFee
        );
        assert(PLAYER_ALICE.balance == STARTING_BALANCE - s_entranceFee);
        assert(s_raffle.getNumberOfPlayers() == 1);
        assert(s_raffle.getPlayer(0) == PLAYER_ALICE);
    }

    function testReceiveWhenPlayerDontSendEth() external {
        // Arrage
        uint256 startingRaffleBalance = address(s_raffle).balance;
        vm.prank(PLAYER_ALICE);
        // Act + Assert #1
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__NotEnoughEthSent.selector,
                s_entranceFee - 1 wei,
                s_entranceFee
            )
        );
        (bool success, ) = address(s_raffle).call{
            value: s_entranceFee - 1234 wei
        }(""); // This call should revert and sucess should be false
        // Assert #2
        assert(success == false);
        assert(address(s_raffle).balance == startingRaffleBalance);
        assert(PLAYER_ALICE.balance == STARTING_BALANCE);
        assert(s_raffle.getNumberOfPlayers() == 0);
    }

    /*//////////////////////////////////////////////////////////////
                           FULFILLRANDOMWORDS
    //////////////////////////////////////////////////////////////*/

    function testFulfillRandomWordsRevertWhenPerformUpkeepHasNotBeenCalled(
        uint256 randomRequestId
    ) external aliceEnterRaffleAndTimeHasPassed skipFork {
        // Act + Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                VRFCoordinatorV2_5Mock.InvalidRequest.selector
            )
        );
        VRFCoordinatorV2_5Mock(s_vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(s_raffle)
        );
    }

    function testFulfillRandomWordsSuccessfulWhenPerformHasBeenCalledAndThenPicksAWinnerAndSendsMoney()
        external
        aliceEnterRaffleAndTimeHasPassed
        skipFork
    {
        // Arrange
        //      Other players enter the raffle
        uint256 additionalPlayers = 5; // Cannot set additionalPlayers = 10 because when we try to transfer the prize to the winner at with address(10), the revert orrcurs. Do not know why
        uint256 startIndex = 1;
        for (uint256 i = startIndex; i < startIndex + additionalPlayers; i++) {
            address player = address(uint160(i));
            //vm.deal(player, STARTING_BALANCE);
            //vm.prank(player);
            hoax(player, STARTING_BALANCE); // Use this for shorter code
            s_raffle.enterRaffle{value: s_entranceFee}();
        }
        uint256 beforePickWinnerTimestamp = s_raffle.getLastTimeStamp();
        //      Call performUpkeep to request to pick a winner
        vm.recordLogs();
        s_raffle.performUpkeep(""); // emits requestId
        Vm.Log[] memory logEntries = vm.getRecordedLogs();
        bytes32 requestId = logEntries[1].topics[1]; // Check function testPerformUpkeepSuccessfulWhenWeDontKnowRequestId to know why using logEntries[1].topics[1]

        // Act + Assert #1
        //vm.expectEmit(true, false, false, false, address(s_raffle));
        //emit Raffle.WinnerPicked(PLAYER_ALICE); // We know the winner is PLAYER_ALICE because only 1 player entered raffle
        //      Pretend to be Chainlink VRF and callfulfillRandomWords
        VRFCoordinatorV2_5Mock(s_vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(s_raffle)
        );

        // Assert #2
        address lastWinner = s_raffle.getLastWinner();
        Raffle.RaffleState raffleState = s_raffle.getRaffleState();
        uint256 winnerBalance = lastWinner.balance;
        uint256 endingTimestamp = s_raffle.getLastTimeStamp();
        uint256 prize = s_entranceFee * (additionalPlayers + 1);
        uint256 expectedWinnerBalance = STARTING_BALANCE -
            s_entranceFee +
            prize;

        assert(raffleState == Raffle.RaffleState.OPEN);
        assert(endingTimestamp > beforePickWinnerTimestamp);
        assert(winnerBalance == expectedWinnerBalance);
    }

    //function testFulfillRandomWordsRevertWhenPerformHasBeenCalledButContractHasNoLinkToPayVrfChainlink()
    //    external
    //    aliceEnterRaffleAndTimeHasPassed
    //{
    //    // Arrange
    //    s_raffle.performUpkeep("");
    //    // Act + Assert
    //    //vm.expectEmit(true, false, false, false, address(s_raffle));
    //    vm.expectRevert(
    //        abi.encodeWithSelector(
    //            VRFCoordinatorV2_5Mock.InsufficientBalance.selector
    //        )
    //    );
    //    emit Raffle.WinnerPicked(PLAYER_ALICE); // We know the winner is PLAYER_ALICE because only 1 player entered raffle
    //    VRFCoordinatorV2_5Mock(s_vrfCoordinator).fulfillRandomWords(
    //        1,
    //        address(s_raffle)
    //    );
    //}
}
