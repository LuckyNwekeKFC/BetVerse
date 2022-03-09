// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";


contract Bet2 is Ownable,ChainlinkClient {

    using Chainlink for Chainlink.Request;

    string public LastGameRequestResult;
    uint8 public LastGameRequestID;
    string public LastGameRequestTitle;
    bytes32 public gamedata;
    
    address private oracle;
    bytes32 private jobId;
    uint256 private fee;

    /**
    Sportsmonk API Details
    Payment Amount: 0.1 LINK
    LINK Token Address: 0xa36085F69e2889c224210F603D836748e7dC0088
    Oracle Address: 0xfF07C97631Ff3bAb5e5e5660Cdf47AdEd8D4d4Fd
    JobID: 491c282eb8b7451699855992d686a20b
     */


    uint256 minimumBetAmount;
    uint8 gamesCounter;
    uint256 dealerBalance;
    address self;

    struct Game {
        uint8 id;
        string seasonID;
        string matchRound;
        string title;
        bool active;
        uint256 prizePool;
        string outcome;
    }


    mapping (uint8 => Game) games;
    mapping (uint8 => address payable[]) gameKeys;
    mapping (uint8 => mapping(address => string)) gameStakes;
    
    constructor() {

        setPublicChainlinkToken();
        oracle = 0xfF07C97631Ff3bAb5e5e5660Cdf47AdEd8D4d4Fd;
        jobId = "491c282eb8b7451699855992d686a20b";
        fee = 0.1 * 10 ** 18;

        gamesCounter = 0;
        dealerBalance = 0 ether;
        // minimumBetAmount = 1 ether;
        minimumBetAmount = 0.1 ether;
        self = address(this);
    }

    function createGame(string memory title,string memory seasonID, string memory matchRound) public onlyOwner returns (uint8) {

        //matchround can  be final,match 4, match 1, etc, while season id can be gotten from the api call
        gamesCounter += 1;

        uint8 gameID = gamesCounter;

        games[gameID] = Game({
            id: gameID,
            seasonID: seasonID,
            matchRound: matchRound,
            title: title, 
            active: true,
            prizePool: 0 ether,
            outcome: ""
        });

        return gameID;
    }

    function getInActiveGames() public view returns (Game[] memory){
        require(gamesCounter > 0, "No Game Yet!");

        Game[] memory allInactiveGames = new Game[](gamesCounter);

        for(uint8 i = 0; i < gamesCounter; i++){
            if(!games[i+1].active){
                allInactiveGames[i] = games[i+1];
            }
        }

        return allInactiveGames;
    }

    function getActiveGames() public view returns (Game[] memory){
        require(gamesCounter > 0, "No Game Yet!");

        Game[] memory allActiveGames = new Game[](gamesCounter);

        for(uint8 i = 0; i < gamesCounter; i++){
            if(games[i+1].active){
                allActiveGames[i] = games[i+1];
            }
        }

        return allActiveGames;
    }

    function getAllGames() public view returns (Game[] memory){
        require(gamesCounter > 0, "No Game Yet!");

        Game[] memory allGames = new Game[](gamesCounter);

        for(uint8 i = 0; i < gamesCounter; i++){
            allGames[i] = games[i+1];
        }

        return allGames;
    }

    function getLatestGameID() public view returns (uint8){
        require(gamesCounter > 0, "No Game Yet!");

        return gamesCounter;
    }

    function getLatestGame() public view returns (Game memory){
        require(gamesCounter > 0, "No Game Yet!");

        uint8 gameID = getLatestGameID();

        return games[gameID];
    }

    function getGame(uint8 gameID) public view returns (Game memory){

        require(games[gameID].id > 0, "Game does not exist!");

        return games[gameID];
    }

    function deleteGame(uint8 gameID) public onlyOwner {
        require(games[gameID].id > 0, "Game does not exist!");

        delete games[gameID];

        gamesCounter -= 1;
    }

    function getGameData(uint8 gameID) public onlyOwner returns (bytes32 requestId){
        require(games[gameID].id > 0, "Game does not exist!");
        // set game to inactive, using the fixture ID perform a request to the API and then call distributePrizes

        Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);
            request.add("endpoint", "match-results");

            request.add("round",  games[gameID].matchRound);

            request.add("season_id", games[gameID].seasonID);

            LastGameRequestID = games[gameID].id;
            LastGameRequestTitle = games[gameID].title;


        return sendChainlinkRequestTo(oracle, request, fee);

    }

    function fulfill(bytes32 _requestId, bytes32 _gamedata) public recordChainlinkFulfillment(_requestId)
    {
            gamedata = _gamedata;

            LastGameRequestResult = bytes32ToString(_gamedata);

        updateGame(LastGameRequestID,LastGameRequestTitle,LastGameRequestResult);

    }

    function bytes32ToString(bytes32 _bytes32) private pure returns (string memory) {
        uint8 i = 0;
        while(i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        
        return string(bytesArray);
    }

    function updateGame(uint8 gameID,string memory title, string memory outcome) public {
        require(games[gameID].id > 0, "Game does not exist!");

        games[gameID].title = keccak256(abi.encodePacked(title)) != keccak256(abi.encodePacked("")) ? title : games[gameID].title;
        
        if(keccak256(abi.encodePacked(outcome)) != keccak256(abi.encodePacked(""))){
            games[gameID].outcome = outcome;
            games[gameID].active = false;

            //distribute prizes won in game
            distributePrizes(gameID);

        }else{
            games[gameID].outcome = games[gameID].outcome;
        }
    }

    function enterGame(uint8 gameID,address payable userWallet, string memory option ) public payable {
        require(msg.value == minimumBetAmount, "Minimum of 1 ETH is required to enter this game!");
        require(games[gameID].id > 0, "Game does not exist!");
        require(games[gameID].active, "Game no longer available!");


        //dealer gets 10% of this stake/bet
        dealerBalance += (msg.value * 10) / 100;

        //game's prize pool gets 90% of this stake/bet
        games[gameID].prizePool += (msg.value * 90) / 100;

        //register user's choice in game
        gameStakes[gameID][userWallet] = option;

        //register game key
        uint256 keysLength = gameKeys[gameID].length;
        gameKeys[gameID][keysLength] = userWallet;
    }

    function distributePrizes(uint8 gameID) public {
        Game memory game = games[gameID];
        //removed the onlyowner modifier to enable it to be called directly when the API returns instead of waiting for the owner to approve

        require(game.id > 0, "Game does not exist!");
        require(!game.active, "Can't distribute prize pool of an active game!");
        require(game.prizePool > 0 ether, "Nothing to earn from this game!");
        require(gameKeys[gameID].length > 0, "No user has entered this game yet!");

        address payable[] memory winners;

        uint256 keysLength = gameKeys[gameID].length;

        for(uint8 i = 0; i < keysLength; i++){
            address payable userAddress = gameKeys[gameID][i];
            string memory option = gameStakes[gameID][userAddress];

            if(keccak256(abi.encodePacked(game.outcome)) == keccak256(abi.encodePacked(option))){
                winners[i] = userAddress;
            }
        }

        //distribute prizes
        if(winners.length > 0){
            uint256 winnersLength = winners.length;
            uint256 amountToDistribute = game.prizePool / winnersLength;

            for(uint8 i = 0; i < winnersLength; i++){
                transfer(winners[i],amountToDistribute);
            }
        }else{
            //if no winners, transfer all game's prize pool to the dealerBalance
            dealerBalance += game.prizePool;
            games[gameID].prizePool -= game.prizePool;
        }
    }

    //allows the bet dealer or owners to withdraw their 10% earnings accrued from each game
    function withdrawDealerEarnings(address payable dealerAddress, uint256 amount) public onlyOwner{
        uint256 amountToWithdraw = amount * 1 ether;

        //the choice of dealerBalance, instead of self.balance prevents the dealer 
        //from rug-pulling funds meant to be distributed to game earners in a prize pool
        require(dealerBalance >= amountToWithdraw, "Can't withdraw more than you currently have!");

        // dealerAddress.transfer(amountToWithdraw);
        transfer(dealerAddress,amountToWithdraw);
    }

    function transfer(address payable to, uint256 amount) public onlyOwner{
        //ensure the contract has enough ether for the transfer
        require(self.balance >= amount, "Insufficient funds!");

        to.transfer(amount);
    }
}
