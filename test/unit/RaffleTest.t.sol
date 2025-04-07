// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {CreateSubscription} from "script/Interactions.s.sol";
import {console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

contract RaffleTest is Test {
    Raffle internal raffle;
    HelperConfig internal helperConfig;
    address private PLAYER_ALICE = makeAddr("PlayerAlice");
    address private PLAYER_BOB = makeAddr("PlayerBob");
    uint256 private STARTING_BALANCE = 100 ether;
    uint256 private entranceFee;
    uint256 private interval;
    address private vrfCoordinator;
    bytes32 private gasLane;
    uint256 private subscriptionId;
    uint32 private callbackGasLimit;
    address private linkTokenContract;

    function setUp() external {
        // Deploy the Raffle contract
        DeployRaffle raffleDeployer = new DeployRaffle();
        (raffle, helperConfig) = raffleDeployer.deployContract();

        // Get network configuration
        HelperConfig.NetworkConfig memory networkConfig = helperConfig
            .getActiveNetworkConfig();
        entranceFee = networkConfig.entranceFee;
        interval = networkConfig.interval;
        vrfCoordinator = networkConfig.vrfCoordinator;
        gasLane = networkConfig.gasLane;
        subscriptionId = networkConfig.subscriptionId;
        callbackGasLimit = networkConfig.callbackGasLimit;
        linkTokenContract = networkConfig.linkTokenContract;

        // Give players some ether
        vm.deal(PLAYER_ALICE, STARTING_BALANCE);
        vm.deal(PLAYER_BOB, STARTING_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                              SIMPLE TEST
    //////////////////////////////////////////////////////////////*/

    function testRaffleInitializesInOpenState() external view {
        // Assert
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleEntranceFeeIsCorrect() external view {
        // Assert
        assert(raffle.getEntranceFee() == entranceFee);
    }

    /*//////////////////////////////////////////////////////////////
                                MODIFIER
    //////////////////////////////////////////////////////////////*/

    modifier aliceEnterRaffleAndTimeHasPassed() {
        vm.prank(PLAYER_ALICE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(raffle.getLastTimeStamp() + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              ENTER RAFFLE
    //////////////////////////////////////////////////////////////*/

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

    function testEnterRaffleRevertWhenRaffleIsNotOpen()
        external
        aliceEnterRaffleAndTimeHasPassed
    {
        // performUpkeep should be successful
        raffle.performUpkeep("");

        // Act + Assert
        // enterRaffle should revert because the raffle is in CALCULATING state
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__RaffleNotOpen.selector)
        );
        vm.prank(PLAYER_BOB);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testEnterRaffleSuccessful() external {
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

    /*//////////////////////////////////////////////////////////////
                              CHECK UPKEEP
    //////////////////////////////////////////////////////////////*/

    function testCheckUpkeepReturnFalseWhenIntervalIsNotPassed() external {
        // Arrage
        vm.prank(PLAYER_ALICE);
        raffle.enterRaffle{value: entranceFee}();
        // Act
        (bool upkeepNeeded, bytes memory performData) = raffle.checkUpkeep(
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
        vm.warp(raffle.getLastTimeStamp() + interval);
        vm.roll(block.number + 1);
        // Act
        (bool upkeepNeeded, bytes memory performData) = raffle.checkUpkeep(
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
        raffle.performUpkeep("");

        // Act
        // 2nd performUpkeep should revert because the raffle is in CALCULATING state
        (bool upkeepNeeded, ) = raffle.checkUpkeep(bytes(""));

        // Assert
        assert(upkeepNeeded == false);
        assert(raffle.getRaffleState() != Raffle.RaffleState.OPEN);
    }

    function testcheckUpkeepReturnTrue()
        external
        aliceEnterRaffleAndTimeHasPassed
    {
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep(bytes(""));

        // Assert
        assert(upkeepNeeded == true);
    }

    /*//////////////////////////////////////////////////////////////
                             PERFORM UPKEEP
    //////////////////////////////////////////////////////////////*/

    function testPerformUpkeepRevertWhenIntervalIsNotPassed() external {
        // Arrage
        vm.prank(PLAYER_ALICE);
        raffle.enterRaffle{value: entranceFee}();
        // Act + Assert
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
        vm.roll(block.number + 1);
        // Act + Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Automation__UpkeepNotNeeded.selector,
                true, // interval has passed
                0, // contract balance
                0, // number of players
                Raffle.RaffleState.OPEN
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertWhenRaffleIsNotOpen()
        external
        aliceEnterRaffleAndTimeHasPassed
    {
        // 1st performUpkeep should be successful
        raffle.performUpkeep("");

        // Act + Assert
        // 2nd performUpkeep should revert because the raffle is in CALCULATING state
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Automation__UpkeepNotNeeded.selector,
                true, // interval has passed
                entranceFee, // contract balance
                1, // number of players
                Raffle.RaffleState.CALCULATING
            )
        );
        raffle.performUpkeep("");
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
        vm.expectEmit(false, false, false, false, address(raffle));
        emit Raffle.WinnerPickRequestSent(0); // requestId is not important because we do not check it
        raffle.performUpkeep(""); // This call will emit requestId with "emit WinnerPickRequestSent(requestId);"

        // Assert #2 // Todo Temporary assertion, need to learn how to skip to when the Raffle finish the calculation
        assert(raffle.getRaffleState() == Raffle.RaffleState.CALCULATING);

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
        raffle.performUpkeep(""); // This call will emit requestId with "emit WinnerPickRequestSent(requestId);"
        Vm.Log[] memory logEntries = vm.getRecordedLogs();
        // logEntries[0] is log of function "requestRandomWords" at line "emit RandomWordsRequested(...);" in file "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol" -> logEntries[1] is log of this "emit WinnerPickRequestSent(requestId);"
        // logEntries[1].topics[0] is keccak256("WinnerPickRequestSent(uint256)") -> logEntries[1].topics[1] is requestId
        bytes32 requestId = logEntries[1].topics[1];

        // Assert
        assert(uint256(requestId) > 0);
        assert(raffle.getRaffleState() == Raffle.RaffleState.CALCULATING);
    }

    /*//////////////////////////////////////////////////////////////
                                FALLBACK
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                                RECEIVE
    //////////////////////////////////////////////////////////////*/

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
}
