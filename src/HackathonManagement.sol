// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Import required OpenZeppelin contracts for security and standard implementations
import "@openzeppelin/contracts/access/Ownable.sol"; // Provides basic access control
import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; // Prevents reentrancy attacks

contract HackathonPrizePool is Ownable, ReentrancyGuard {
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

    // Function to create a new hackathon
    function createHackathon(
        bool _isCrowdfunded,
        string calldata hackathonId
    ) external payable {
        // Get reference to new hackathon in storage
        Hackathon storage hackathon = hackathons[hackathonId];

        // Initialize hackathon data
        hackathon.id = hackathonId;
        hackathon.creator = msg.sender;
        hackathon.isCrowdfunded = _isCrowdfunded;
        hackathon.basePrize = msg.value;
        hackathon.state = HackathonState.OPEN;

        emit HackathonCreated(
            hackathonId,
            msg.sender,
            msg.value,
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
        uint256 _amount,
        address _contributor
    ) external nonReentrant {
        Hackathon storage hackathon = hackathons[_hackathonId];

        require(hackathon.isCrowdfunded, "Hackathon is not crowdfunded");
        require(
            hackathon.state != HackathonState.COMPLETED,
            "Hackathon is completed"
        );
        require(_amount > 0, "Contribution amount must be greater than zero");

        // Update contribution amount
        hackathon.contributionsPerAddress[_contributor] += _amount;
        hackathon.contributions += _amount;

        emit ContributionAdded(_hackathonId, _contributor, _amount);
    }

    // Function for updating hackathon state - only contract owner can call
    function updateHackathonState(
        string calldata _hackathonId,
        HackathonState _newState
    ) external onlyOwner {
        Hackathon storage hackathon = hackathons[_hackathonId];
        require(
            uint8(_newState) > uint8(hackathon.state),
            "Cannot revert state"
        );

        hackathon.state = _newState;
        emit HackathonStateChanged(_hackathonId, _newState);
    }

    // Function for announcing winning teams - only contract owner can call
    function announceWinners(
        string calldata _hackathonId,
        address _winningParticipant
    ) external onlyOwner {
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

    function claimPrize(
        string calldata _hackathonId,
        address winnerAddress,
        bytes memory paymentRef,
        address ethFeeProxy
    ) external payable nonReentrant onlyOwner {
        Hackathon storage hackathon = hackathons[_hackathonId];

        require(
            hackathon.state == HackathonState.COMPLETED,
            "Hackathon not completed"
        );
        require(
            hackathon.participants[winnerAddress].isWinner,
            "Address is not a winner"
        );

        bytes memory data = abi.encodeWithSignature(
            "transferWithReferenceAndFee(address,bytes,uint256,address)",
            payable(winnerAddress),
            paymentRef,
            0,
            payable(address(0))
        );

        (bool callSuccess, ) = address(ethFeeProxy).call{value: msg.value}(
            data
        );

        require(callSuccess, "Failed Call to EthFeeProxy Contract");
    }
}
