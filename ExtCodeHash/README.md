# What is the EXTCODEHASH?

The EVM opcode EXTCODEHASH was added on February 28, 2019 via EIP-1052. Not only does it help to reduce external function calls for compiled Solidity contracts, it also adds additional functionality. It gives you the hash of the code from an address. Since only contract addresses have code, you could use this to determine if an address is a smart contract (taken from Openzeppelin-contracts):

```
function isContract(address account) internal view returns (bool) {
    bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

    bytes32 codeHash;
    assembly { codeHash := extcodehash(account) }

    return (codeHash != accountHash && codeHash != 0x0);
}
```

The account hash of 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned for non-contract addresses, so-called Externally Owned Account (EOA). If an account was not used yet, the code hash of 0x0 will be returned, see the specification. Be aware though that in some cases this will return false even for contracts, when they are just created or when they have been destroyed. But if it returns true, you can be sure that it's a smart contract.

## Whitelisting contract bytecodes in your system

The other interesting use case is whitelisting bytecodes. You can develop and compile different smart contract implementations that you want to allow in your system. Then you get the hash of that contract, e.g., just by using another contract with an extcodehash view function. Once you have the allowed bytecode hashes, you can whitelist them and allow only whitelisted contracts to be added and used in your system:

```
contract ExtCodeHashExample is Ownable {
    mapping (ExternalContractInterface=>bool) public isAddedContract;
    mapping (bytes32=>bool) public isWhitelistedByteCode;
    ExternalContractInterface[] public externalContracts;

    function addWhitelistedContractByteCode(bytes32 contractByteCode) external onlyOwner {
        isWhitelistedByteCode[contractByteCode] = true;
    }

    function registerNewContract(ExternalContractInterface externalContract) external {
        bytes32 codeHash;
        assembly { codeHash := extcodehash(externalContract) }

        require(isWhitelistedByteCode[codeHash], "Contract byte code is not whitelisted");
        require(!isAddedContract[externalContract], "Contract already added");

        externalContracts.push(externalContract);
        isAddedContract[externalContract] = true;
    }
}
```

That's great. We keep a list of every externally registered contract inside externalContracts. Anyone can create and register a contract, but thanks to the check of require(isWhitelistedByteCode[codeHash]), we know that those contracts must behave exactly like we want them to. Let's look at a gambling system as an example for how you could make use of such a system.

## Gambling with external contracts

We will define an ExternalContractInterface. This interface will be used in our system and anyone can create contracts and register them in our system. Think of them in Defi terms as liquidity providers.

```
interface ExternalContractInterface {
    function game() external returns(ExtCodeHashExample);
    function payoutToWinner(address winner) external;
    function withdrawTo(uint roundId, address receiver) external;
    receive() external payable;
}
```

Player vs. Contracts: Now we will add the main function playGame. A user can send 0.55 ETH and the system will 'randomly' choose a winner, the player or the contracts. If the player wins, the current external contract is chosen to pay him 1 ETH. Once a round is over, meaning each external contract played one time, an external contract is chosen 'randomly' as winner. This external contract will be able to withdraw all of the ticket fees for the round.

```
function playGame() external payable {
    require(msg.value == totalPrice, "You must send 0.55 ETH");

    if (now % 2 == 0) { // unsafe randomness
        externalContracts[nextContractIndex].payoutToWinner(msg.sender);
    }

    nextContractIndex = (nextContractIndex + 1) % externalContracts.length;

    if (nextContractIndex == 0) {
        earningsForRound[roundId] = externalContracts.length * totalPrice;
        contractWinnerForRound[roundId] = externalContracts[now % externalContracts.length]; // unsafe randomness
        roundId++;
    }
}
```
Now we also need a withdraw function, so that the winning external contract can receive his funds. We could send the ETH directly to the contract, but we need a defined way for contract owners to withdraw money, so that they can't empty the whole contract whenever they want.

```
function withdraw(uint withdrawRoundId, address receiver) external {
    require(
        ExternalContractInterface(msg.sender) == contractWinnerForRound[withdrawRoundId],
        "Only winning contract can withdraw"
    );
    
    contractWinnerForRound[withdrawRoundId] = ExternalContractInterface(0); // prevent further withdrawals
    
    (bool success,) = receiver.call{value: earningsForRound[withdrawRoundId]}('');
    require(success, "Withdraw transfer failed");
}
```

Now let's look at an ExternalContractInterface implementation. This will implement the payoutToWinner and withdrawTo interface functions. This will be our accepted and honest implementation:

  ```
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
```

If you check the bytecode hash of this contract, it will be 0x0f3c98d10c122fd1440d0b59341c9b144658c79f7b3a612a99b7e970339d0ee4. This will be our whitelisted implementation. It fairly sends out 1 ETH to the winner.

Now imagine someone would create a contract with the following function:
```
function payoutToWinner(address winner) external override {
    require(msg.sender == address(game), 'Only game can call this');

    (bool success,) = attackerAddress.call{value: 1 ether}('');
    require(success, "Liquidity transfer failed");
}
```

This contract behaves maliciously. Instead of sending 1 ETH to the winner of the game, it sends it to the attacker. But since the bytecode is different, the hash will be 0x68af5afef67164fa697c8b978f3ee5dd0d799e151ef236bcaec53fa4d68895a7. This is not a whitelisted hash, so the attacker won't be able to register his contract in our system.

Full example: You can find a fully working example here that is perfectly usable inside Remix. Make sure to transfer ETH to the deployed interface contracts by clicking the 'CALLDATA Transact' button which transfers ETH using the fallback function. You can use the getExtCodeHash view function to read a deployed contract's bytecode and then whitelist it. The full example also automatically removes contracts with an ETH balance that is too low.

