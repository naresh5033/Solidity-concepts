// SPDX-License-Identifier: MIT
pragma solidity 0.6.10;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

interface ExternalContractInterface {
    function game() external returns(ExtCodeHashExample);
    function payoutToWinner(address winner) external;
    function withdrawTo(uint roundId, address receiver) external;
    receive() external payable;
}

contract ExternalContractInterfaceHonest is ExternalContractInterface {
    ExtCodeHashExample public override game;
    
    constructor(ExtCodeHashExample _game) public {
        game = _game;
    }
    
    function payoutToWinner(address winner) external override {
        require(msg.sender == address(game), 'Only game can call this');
        
        (bool success,) = winner.call{value: 1 ether}('');
        require(success, "Liquidity transfer failed");
    }
    
    function withdrawTo(uint roundId, address receiver) external override {
        game.withdraw(roundId, receiver);
    }
    
    receive() external override payable {}
}

contract ExternalContractInterfaceMalicious is ExternalContractInterface {
    address constant private owner = 0xeF42725A63691fdbB0A1802cdCC94792B749781e;
    ExtCodeHashExample public override game;

    constructor(ExtCodeHashExample _game) public {
        game = _game;
    }

    function payoutToWinner(address winner) external override {
        require(msg.sender == address(game), 'Only game can call this');
    
        (bool success,) = owner.call{value: 1 ether}('');
        require(success, "Liquidity transfer failed");
    }

    function withdrawTo(uint roundId, address receiver) external override {
        game.withdraw(roundId, receiver);
    }

    receive() external override payable {}
}

contract ExtCodeHashExample is Ownable {
    uint constant entryTicketCost = 0.5 ether;
    uint constant fees = 0.05 ether;
    uint constant totalPrice = entryTicketCost + fees;
    
    mapping (ExternalContractInterface=>bool) public isAddedContract;
    mapping (uint=>ExternalContractInterface) public contractWinnerForRound;
    mapping (uint=>uint) public earningsForRound;
    mapping (bytes32=>bool) public isWhitelistedByteCode;
    
    ExternalContractInterface[] public externalContracts;
    uint public roundId = 0;
    uint public nextContractIndex = 0;
    
    function addWhitelistedContractByteCode(bytes32 contractByteCode) external onlyOwner {
        isWhitelistedByteCode[contractByteCode] = true;
    }

    function registerNewContract(ExternalContractInterface externalContract) external {
        require(externalContract.game() == this, "Contract must set this instance as game");
        require(!isAddedContract[externalContract], "Contract already added");

        bytes32 codeHash;
        assembly { codeHash := extcodehash(externalContract) }
    
        require(isWhitelistedByteCode[codeHash], "Contract byte code is not whitelisted");
        
        externalContracts.push(externalContract);
        isAddedContract[externalContract] = true;
    }
    
    function getExtCodeHash(address thecontract) external view returns(bytes32) {
        bytes32 codeHash;
        assembly { codeHash := extcodehash(thecontract) }
        
        return codeHash;
    }
    
    function playGame() external payable {
        require(msg.value == totalPrice, "You must send 0.55 ETH");
        
        if (address(externalContracts[nextContractIndex]).balance < 1 ether) {
            _removeCurrentContract();
    
            (bool success,) = msg.sender.call{value: msg.value}('');
            require(success, "Refund sender failed");
            
            return;
        }
    
        if (now % 2 == 0) { // unsafe randomness
            externalContracts[nextContractIndex].payoutToWinner(msg.sender);
        }
    
        _moveToNextContract();
    }
    
    function withdraw(uint withdrawRoundId, address receiver) external {
        require(
            ExternalContractInterface(msg.sender) == contractWinnerForRound[withdrawRoundId],
            "Only winning contract can withdraw"
        );
        
        contractWinnerForRound[withdrawRoundId] = ExternalContractInterface(0); // prevent further withdrawals
        
        (bool success,) = receiver.call{value: earningsForRound[withdrawRoundId]}('');
        require(success, "Withdraw transfer failed");
    }
    
    function _removeCurrentContract() private {
        isAddedContract[externalContracts[nextContractIndex]] = false;
        externalContracts[nextContractIndex] = externalContracts[externalContracts.length - 1];
        externalContracts.pop();
    }
    
    function _moveToNextContract() private {
        nextContractIndex = (nextContractIndex + 1) % externalContracts.length;
        
        if (nextContractIndex == 0) {
            earningsForRound[roundId] = externalContracts.length * totalPrice;
            contractWinnerForRound[roundId] = externalContracts[now % externalContracts.length]; // unsafe randomness
            roundId++;
        }
    }
    
    receive() external payable {}
}