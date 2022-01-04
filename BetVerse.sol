// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";

contract BetVerse is Ownable {

    uint256 minimumBetAmount;
    uint8 gamesCounter;
    uint256 dealerBalance;
    address self;

    struct Game {
        uint8 id;
        string title;
        bool active;
        uint256 prizePool;
        string outcome;
    }

    mapping (uint8 => Game) games;
    mapping (uint8 => address payable[]) gameKeys;
    mapping (uint8 => mapping(address => string)) gameStakes;
    
    constructor() {
        gamesCounter = 0;
        dealerBalance = 0 ether;
        minimumBetAmount = 1 ether;
        self = address(this);
    }

    function createGame(string memory title) public onlyOwner returns (uint8) {
        gamesCounter += 1;

        uint8 gameID = gamesCounter;

        games[gameID] = Game({
            id: gameID,
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

    function updateGame(uint8 gameID,string memory title, string memory outcome) public onlyOwner {
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

    function enterGame(uint8 gameID, address payable userWallet, string memory option ) public payable {
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

    function distributePrizes(uint8 gameID) public onlyOwner{
        Game memory game = games[gameID];

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
