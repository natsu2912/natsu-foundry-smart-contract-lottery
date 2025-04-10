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

//---------------------------------------------
// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {VRFConsumerBaseV2Plus} from "@chainlink/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/src/v0.8/automation/AutomationCompatible.sol";

/**
 * @title This is the Raffle contract
 * @author natsu
 * @notice This contract is used for a Raffle (Lottery Smart Contract) System
 * @dev It implements Chainlink VRFv2.5 for random number generation and Chainlink Automation
 */
contract Raffle is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
    /** Custom Errors */
    /*** Custom Errors related to Raffle Contracts */
    error Raffle__NotEnoughEthSent(uint256 sentValue, uint256 minValue);
    error Raffle__IntervalNotPassed();
    error Raffle__PrizeTransferFailed();
    error Raffle__RaffleNotOpen();
    /*** Custom Errors related to Chainlink VRF */
    //...

    /*** Custom Errors related to Chainlink Automation */
    error Automation__UpkeepNotNeeded(
        bool isIntervalPassed,
        uint256 contractBalance,
        uint256 numberOfPlayers,
        uint256 raffleState
    );

    /** Type Declarations */
    /*** Enum */
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
    }

    /** State Variables */
    /***  Our Raffle contract related variables */
    uint256 private immutable i_entranceFee;
    // @dev Duration for lottery in secondsrr
    uint256 private immutable i_interval;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address payable private s_lastWinner;
    RaffleState private s_raffleState;

    /***  Chainlink VRF related variables */
    //VRFV2PlusClient private immutable i_vrfCoordinator;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    bytes32 private immutable i_gasLane;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    uint32 private constant NUM_WORDS = 1;

    /** Events */
    event EnteredRaffle(address indexed player);
    event WinnerPicked(address indexed winner);
    event WinnerPickRequestSent(uint256 indexed requestId);

    /** Modifiers */
    modifier RaffleIsOpen() {
        // Check to see if the raffle is open. If not open, do not allow to enter this function
        if (s_raffleState != RaffleState.OPEN) revert Raffle__RaffleNotOpen();
        _;
    }

    /** Functions: Start */
    /*** Constructor*/
    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;

        //i_vrfCoordinator = VRFV2PlusClient(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
    }

    /*** receive and fallback functions */
    receive() external payable {
        enterRaffle();
    }

    fallback() external payable {
        enterRaffle();
    }

    /*** external Functions: Start */

    /**
     * @dev performUpKeep do these steps
     * 1. Get a random number
     * 2. Use the random number to pick a player
     * 3. Automatically called
     */
    function performUpkeep(bytes calldata /* performData */) external override {
        (bool upkeepNeeded, bytes memory _performData) = checkUpkeep(bytes(""));
        if (!upkeepNeeded) {
            revert Automation__UpkeepNotNeeded(
                abi.decode(_performData, (bool)),
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        // Do "pickWinner"
        pickWinner();
    }

    /*** external Functions: End */

    /*** public Functions: Start */
    function enterRaffle() public payable RaffleIsOpen {
        //require(msg.value >= i_entranceFee, Nnot enough ETH");
        //require(msg.value >= i_entranceFee, NotEnoughEth());
        /**
         * @dev This check is the best gas efficient way to check if the user has sent enough ETH (compare to the above 2 lines)
         */
        if (msg.value < i_entranceFee)
            revert Raffle__NotEnoughEthSent(msg.value, i_entranceFee);

        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev This is the function that the Chainlink Automation nodes call
     * They look for 'upkeepNeeded' to return true.
     * The following should be true for this to return true:
     *     1. The time interval has passed between raffle runs
     *     2. The lottery is open (Not calculating)
     *     3. The contract has ETH
     *     4. There are players registered
     *     5. Implicitly, you subscription is funded with LINK
     * _param - ignore
     * @return upkeepNeeded - true if it's time to pick a winner and restart the lottery
     * _return - ignore
     */
    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        bool isIntervalPassed = (block.timestamp - s_lastTimeStamp) >=
            i_interval;
        bool isRaffleOpen = RaffleState.OPEN == s_raffleState;
        bool contractHasBalance = address(this).balance > 0;
        bool contractHasPlayers = s_players.length > 0;
        upkeepNeeded = (isIntervalPassed &&
            isRaffleOpen &&
            contractHasBalance &&
            contractHasPlayers);
        performData = abi.encode(isIntervalPassed);
        return (upkeepNeeded, performData);
    }

    /*** public Functions: End */

    /*** internal Functions: Start */
    // @dev fulfillRandomWords function
    function fulfillRandomWords(
        uint256 /* _requestId */,
        //    uint256[] memory randomWords
        uint256[] calldata _randomWords
    ) internal override {
        // @dev This function is called by Chainlink VRF Coordinator

        /**** Effects */
        // pick a winner here, send him the reward and reset the raffle
        uint256 numberOfPlayers = s_players.length;
        uint256 indexOfWinner = _randomWords[0] % numberOfPlayers;
        address payable winner = s_players[indexOfWinner];
        // Assign the winner to state variable s_lastWinner
        s_lastWinner = winner;
        // Set the raffle state to OPEN
        s_raffleState = RaffleState.OPEN;
        // Reset the players array
        s_players = new address payable[](0);
        // Reset the last timestamp
        s_lastTimeStamp = block.timestamp;

        // Emit the event
        emit WinnerPicked(winner);

        /**** Interactions (External contract interactions) */
        // Transfer prize to winner
        (bool success, ) = s_lastWinner.call{value: address(this).balance}("");
        //require(success, "Prize transfer failed");
        if (!success) revert Raffle__PrizeTransferFailed();
    }

    // 1. Get a random winner
    // 2. Use a random number to pick a winner from players
    // 3. Automatically called
    // @dev Do not need to check "RaffleIsOpen" because parent contract already checks
    function pickWinner() internal {
        /**** Checks */
        // Do not need to check if enough time has passed because parent contract already checks

        /**** Effects */
        // Set the state to CALCULATING
        s_raffleState = RaffleState.CALCULATING;

        /**** Interactions (External contract interactions) */
        // Request random number from Chainlink VRF
        VRFV2PlusClient.RandomWordsRequest memory randomWordsRequestData = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_gasLane,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to false to use LINK, true to use native (Sepolia ETH)
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            randomWordsRequestData
        );
        emit WinnerPickRequestSent(requestId);
    }

    /*** internal Functions: End */

    /*** private Functions: Start */

    /*** private Functions: End */

    /*** view & pure Functions: Start */
    /**** Getter Functions: Start */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 index) external view returns (address player) {
        return s_players[index];
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getLastWinner() external view returns (address) {
        return s_lastWinner;
    }

    /**** Getter Functions: End */
    /*** view & pure Functions: End */

    /** Functions: End */
}
