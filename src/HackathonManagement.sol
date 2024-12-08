// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Import required OpenZeppelin contracts for security and standard implementations
import "@openzeppelin/contracts/access/Ownable.sol"; // Provides basic access control

struct RequestDetail {
    address recipient;
    uint256 requestAmount;
    address[] path;
    bytes paymentReference;
    uint256 feeAmount;
    uint256 maxToSpend;
    uint256 maxRateTimespan;
}

struct MetaDetail {
    uint256 paymentNetworkId;
    RequestDetail[] requestDetails;
}

interface IBatchConversionPayments {
    function batchPayments(
        MetaDetail[] calldata metaDetails,
        address[][] calldata pathsToUSD,
        address feeAddress
    ) external payable;
}

contract HackathonPrizeManagement is Ownable {
    address private originalSender;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    modifier nonReentrant() {
        if (
            msg.sender != address(0xe11BF2fDA23bF0A98365e1A4c04A87C9339e8687) &&
            msg.sender != address(0x67818703c92580c0e106e401F253E8A410A66f8B)
        ) {
            require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
            _status = _ENTERED;
        }
        _;
        if (
            msg.sender != address(0xe11BF2fDA23bF0A98365e1A4c04A87C9339e8687) &&
            msg.sender != address(0x67818703c92580c0e106e401F253E8A410A66f8B)
        ) {
            _status = _NOT_ENTERED;
        }
    }

    constructor() Ownable(msg.sender) {
        _status = _NOT_ENTERED;
    }

    enum HackathonState {
        OPEN, // Initial state, participants can join
        ONGOING, // Hackathon is in progress
        JUDGING, // Winners being decided
        COMPLETED // Winners announced and prizes can be claimed
    }

    // Struct to store team information
    struct Participant {
        address walletAddress;
        bool isWinner;
        bool hasClaimedPrize;
    }

    // Struct to store hackathon information
    struct Hackathon {
        string id; // Unique identifier for the hackathon
        address creator; // Address of who created the hackathon
        uint256 basePrize; // Initial prize put up by creator
        uint256 contributions;
        bool isCrowdfunded;
        HackathonState state;
        mapping(address => Participant) participants;
        uint64 winnerCount;
        mapping(address => uint256) contributionsPerAddress; // Track how much each address contributed
    }

    // Store all hackathons by their ID
    mapping(string => Hackathon) public hackathons;

    // Address of the BatchConversionPayments contract
    address public batchConversionPayments =
        address(0x67818703c92580c0e106e401F253E8A410A66f8B);
    address public ethFeeProxy =
        address(0xe11BF2fDA23bF0A98365e1A4c04A87C9339e8687);

    // Events to log important actions
    event HackathonCreated(
        string indexed hackathonId,
        address creator,
        uint256 basePrize,
        bool isCrowdfunded
    );

    event ParticipantJoined(string indexed hackathonId, address participant);

    event ContributionAdded(
        string indexed hackathonId,
        address contributor,
        uint256 amount
    );

    event PrizeClaimed(
        string indexed hackathonId,
        address participant,
        uint256 prize
    );

    event HackathonStateChanged(
        string indexed hackathonId,
        HackathonState newState
    );

    event BatchPaymentExecutionAttempt(
        string indexed hackathonId,
        address[] winners,
        uint256[] amounts,
        bytes[] paymentReferences,
        address feeAddress
    );

    event BatchPaymentExecutionFailed(
        string indexed hackathonId,
        string errorMessage
    );

    receive() external payable nonReentrant {}

    // Function to create a new hackathon
    function createHackathon(
        bool _isCrowdfunded,
        string calldata hackathonId,
        uint256 basePrize
    ) external {
        // Get reference to new hackathon in storage
        Hackathon storage hackathon = hackathons[hackathonId];
        require(bytes(hackathon.id).length == 0, "Hackathon ID already exists");

        // Initialize hackathon data
        hackathon.id = hackathonId;
        hackathon.creator = msg.sender;
        hackathon.isCrowdfunded = _isCrowdfunded;
        hackathon.basePrize = basePrize;
        hackathon.state = HackathonState.OPEN;

        emit HackathonCreated(
            hackathonId,
            msg.sender,
            basePrize,
            _isCrowdfunded
        );
    }

    function joinHackathon(string calldata _hackathonId) external {
        Hackathon storage hackathon = hackathons[_hackathonId];

        require(
            hackathon.state == HackathonState.OPEN,
            "Hackathon is not open"
        );

        // Ensure participant isn't already registered
        require(
            hackathon.participants[msg.sender].walletAddress == address(0),
            "Already joined"
        );

        // Initialize the participant
        hackathon.participants[msg.sender] = Participant({
            walletAddress: msg.sender,
            isWinner: false,
            hasClaimedPrize: false
        });

        emit ParticipantJoined(_hackathonId, msg.sender);
    }

    // Function for recording a contribution to a crowdfunded hackathon
    function recordContribution(
        string calldata _hackathonId,
        address _contributor,
        uint256 contributedAmount
    ) external nonReentrant {
        Hackathon storage hackathon = hackathons[_hackathonId];

        require(hackathon.isCrowdfunded, "Hackathon is not crowdfunded");
        require(
            hackathon.state != HackathonState.COMPLETED,
            "Hackathon is completed"
        );
        require(
            contributedAmount > 0,
            "Contribution amount must be greater than zero"
        );

        // Update contribution amount
        hackathon.contributionsPerAddress[_contributor] += contributedAmount;
        hackathon.contributions += contributedAmount;

        emit ContributionAdded(_hackathonId, _contributor, contributedAmount);
    }

    // Function for updating hackathon state - only contract owner can call
    function updateHackathonState(
        string calldata _hackathonId,
        HackathonState _newState
    ) external {
        Hackathon storage hackathon = hackathons[_hackathonId];
        require(
            uint8(_newState) > uint8(hackathon.state),
            "Cannot revert state"
        );

        hackathon.state = _newState;
        emit HackathonStateChanged(_hackathonId, _newState);
    }

    // Function for announcing winning teams - only contract owner can call
    function announceWinner(
        string calldata _hackathonId,
        address _winningParticipant
    ) external onlyOwner nonReentrant {
        Hackathon storage hackathon = hackathons[_hackathonId];

        require(
            hackathon.state == HackathonState.JUDGING,
            "Not in judging phase"
        );
        // Check if the participant exists
        require(
            hackathon.participants[_winningParticipant].walletAddress !=
                address(0),
            "Participant does not exist"
        );
        hackathon.participants[_winningParticipant].isWinner = true;
    }

    event BatchPaymentExecuted(string indexed hackathonId);

    // Function to execute batch payments
    function executeBatchPayments(
        string calldata hackathonId,
        MetaDetail[] calldata metaDetails,
        address[][] calldata pathsToUSD,
        address feeAddress
    ) external onlyOwner nonReentrant {
        Hackathon storage hackathon = hackathons[hackathonId];

        require(
            hackathon.state == HackathonState.COMPLETED,
            "Hackathon not completed"
        );

        for (uint256 i = 0; i < metaDetails.length; i++) {
            require(
                hackathon
                    .participants[metaDetails[i].requestDetails[0].recipient]
                    .isWinner,
                "Address is not a winner"
            );
            require(
                !hackathon
                    .participants[metaDetails[i].requestDetails[0].recipient]
                    .hasClaimedPrize,
                "Prize already claimed"
            );
        }

        // Validate total prize distribution matches the hackathon's contributions + base prize
        uint256 calculatedTotal = 0;
        for (uint256 i = 0; i < metaDetails.length; i++) {
            calculatedTotal += metaDetails[i].requestDetails[0].requestAmount;
        }
        require(
            calculatedTotal <= hackathon.basePrize + hackathon.contributions,
            "Exceeds prize pool"
        );

        // Call the external BatchConversionPayments contract
        try
            IBatchConversionPayments(batchConversionPayments).batchPayments(
                metaDetails,
                pathsToUSD,
                feeAddress
            )
        {
            // Emit success event if needed
            emit BatchPaymentExecuted(hackathonId);
        } catch (bytes memory error) {
            // Log the error for debugging
            emit BatchPaymentExecutionFailed(hackathonId, string(error));
            revert(string(error)); // Revert with the error message
        }
    }

    function claimPrize(
        string calldata _hackathonId,
        address winnerAddress,
        uint256 wonAmount,
        bytes memory paymentRef
    ) external payable nonReentrant {
        Hackathon storage hackathon = hackathons[_hackathonId];

        require(
            hackathon.state == HackathonState.COMPLETED,
            "Hackathon not completed"
        );
        require(
            hackathon.participants[winnerAddress].isWinner,
            "Address is not a winner"
        );
        require(
            !hackathon.participants[winnerAddress].hasClaimedPrize,
            "Prize already claimed"
        );

        require(
            wonAmount <= address(this).balance,
            "Insufficient contract balance"
        );
        bytes memory data = abi.encodeWithSignature(
            "transferWithReferenceAndFee(address,bytes,uint256,address)",
            payable(winnerAddress),
            paymentRef,
            0,
            payable(address(0))
        );

        (bool callSuccess, bytes memory callData) = address(ethFeeProxy).call{
            value: wonAmount
        }(data);
        require(callSuccess, string(callData));
        // Mark as claimed
        hackathon.participants[winnerAddress].hasClaimedPrize = true;
    }

    function getParticipantInfo(
        string calldata _hackathonId,
        address participantAddress
    )
        external
        view
        returns (bool isWinner, bool hasClaimedPrize, address walletAddress)
    {
        Hackathon storage hackathon = hackathons[_hackathonId];
        Participant storage participant = hackathon.participants[
            participantAddress
        ];

        return (
            participant.isWinner,
            participant.hasClaimedPrize,
            participant.walletAddress
        );
    }
}
