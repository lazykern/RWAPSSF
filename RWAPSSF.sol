// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;
import "./CommitReveal.sol";

contract RPS is CommitReveal {
    enum Choice { Rock, Water, Air, Paper, Sponge, Scissors, Fire }

    struct Player {
        Choice choice;
        address addr;
        uint256 fund;
    }

    uint256 public constant TIMEOUT = 1 days;

    uint256 public constant MAX_PLAYERS = 3;

    mapping(uint256 => Player) public player;
    mapping(address => uint256) public playerIdx;
 
    uint256 public numPlayer = 0;
    uint256 public reward = 0;
    uint256 public numCommit = 0;
    uint256 public numRevealed = 0;
    uint256 public latestActionTimestamp = 0;

    function addPlayer() public payable {
        require(numPlayer < MAX_PLAYERS, "Maximum number of players reached");
        require(msg.value == 1 ether, "Insufficient or excessive amount sent");

        reward += msg.value;
        player[numPlayer].fund = msg.value;
        player[numPlayer].addr = msg.sender;
        playerIdx[msg.sender] = numPlayer;
        numPlayer++;

        latestActionTimestamp = block.timestamp;
    }

    function getChoiceHash(Choice choice, uint256 salt)
        public
        view
        returns (bytes32)
    {
        require(uint256(choice) <= 6, "Invalid choice");
        return getSaltedHash(bytes32(uint256(choice)), bytes32(salt));
    }

    function commitChoice(bytes32 choiceHash) public {
        require(choiceHash != 0, "Invalid choice hash");
        require(numPlayer == MAX_PLAYERS, "Not enough players");
        require(msg.sender == player[playerIdx[msg.sender]].addr, "Invalid sender");
        require(commits[msg.sender].commit == 0, "Already committed");
        require(!commits[msg.sender].revealed, "Already revealed");

        commit(choiceHash);

        numCommit++;

        latestActionTimestamp = block.timestamp;
    }

    function revealChoice(Choice choice, uint256 salt) public {
        require(uint256(choice) <= 6, "Invalid choice");
        require(numPlayer == MAX_PLAYERS, "Not enough players");
        require(numCommit == MAX_PLAYERS, "Not all players have committed");
        require(msg.sender == player[playerIdx[msg.sender]].addr, "Invalid sender");

        revealAnswer(bytes32(uint256(choice)), bytes32(salt));
        player[playerIdx[msg.sender]].choice = choice;

        numRevealed++;

        if (numRevealed == MAX_PLAYERS) {
            _checkWinnerAndPay();
        }

        latestActionTimestamp = block.timestamp;
    }

    function _checkWinnerAndPay() private {
        uint256 p0Choice = uint256(player[0].choice);
        uint256 p1Choice = uint256(player[1].choice);
        uint256 p2Choice = uint256(player[2].choice);
        uint256[] memory points = new uint256[](3);

        // Win: +3, Draw: +1, Lose: +0
        // check with all players

        points[0] = _checkWin(p0Choice, p1Choice);
        points[0] = _checkWin(p0Choice, p2Choice);

        points[1] = _checkWin(p1Choice, p0Choice);
        points[1] = _checkWin(p1Choice, p2Choice);

        points[2] = _checkWin(p2Choice, p0Choice);
        points[2] = _checkWin(p2Choice, p1Choice);

        uint256 maxPointCount = 0;
        uint256 maxPoint = 0;
        uint256 winner = 0;
        for (uint256 i = 0; i < 3; i++) {
            if (points[i] > maxPoint) {
                maxPoint = points[i];
                winner = i;
            }
            if (points[i] == maxPoint) {
                maxPointCount += 1;
            }
        }

        // if maxPointCount == 1, and pay to player that have maxPoint
        // if maxPointCount > 1, and pay to player that have point == maxPoint
        if (maxPointCount == 1) {
            address payable account = payable(player[winner].addr);
            account.transfer(reward);
        } else {
            for (uint256 i = 0; i < 3; i++) {
                if (points[i] == maxPoint) {
                    address payable account = payable(player[i].addr);
                    account.transfer(reward / maxPointCount);
                }
            }
        }

        _reset();
    }

    enum Result {WIN, LOSE, DRAW}

    function _checkWin(uint256 p0Choice, uint256 p1Choice) private pure returns(uint256) {
        if ((p1Choice + 1) % 7 == p0Choice || (p1Choice + 2) % 7 == p0Choice || (p1Choice + 3) % 7 == p0Choice) {
            return 3;
        } else if ((p0Choice + 1) % 7 == p1Choice || (p0Choice + 2) % 7 == p1Choice || (p0Choice + 3) % 7 == p1Choice) {
            return 0;
        } else {
            return 1;
        }

    }
    
    function checkTimeout() public {
        require(block.timestamp > latestActionTimestamp + TIMEOUT, "Timeout has not occurred yet");
        require(msg.sender == player[0].addr || msg.sender == player[1].addr || msg.sender == player[2].addr, "Invalid sender");
        require(numPlayer > 0, "No players registered");


        address payable account0 = payable(player[0].addr);

        // Refund to first player if [number of player is not enough]
        if (numPlayer < MAX_PLAYERS) {
            account0.transfer(reward);
            
            _reset();
            return;
        }

        address payable account1 = payable(player[1].addr);
        
        // Refund to all player if [any player doesn't commit in time] or [all players commit but not reveal]
        if (numCommit < 2 || numRevealed == 0) {
            account0.transfer(player[0].fund);
            account1.transfer(player[1].fund);
            
            _reset();
            return;
        }

        address payable account2 = payable(player[2].addr);
        
        // Refund to all player if [any player doesn't commit in time] or [all players commit but not reveal]
        if (numCommit < 3 || numRevealed == 0) {
            account0.transfer(player[0].fund);
            account1.transfer(player[1].fund);
            account2.transfer(player[2].fund);
            
            _reset();
            return;
        }

        // Refund to player that reveal if [all players reveal]
        if (numRevealed < 3) {
            for (uint256 i = 0; i < 3; i++) {
                if (commits[player[i].addr].revealed) {
                    address payable account = payable(player[i].addr);
                    account.transfer(player[i].fund);
                } else {
                    payable(msg.sender).transfer(player[i].fund);
                }
            }
        }
    }

    function _reset() private {
        numPlayer = 0;
        reward = 0;
        numCommit = 0;
        numRevealed = 0;
        latestActionTimestamp = 0;
        delete commits[player[0].addr];
        delete commits[player[1].addr];
        delete commits[player[2].addr];
        delete player[0];
        delete player[1];
        delete player[2];
    }
}
