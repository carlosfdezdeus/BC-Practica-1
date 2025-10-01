// SPDX-License-Identifier: Unlicenced
pragma solidity 0.8.30;

contract TokenContract {
    
    address public owner;  // Dirección del propietario del contrato
    struct Receivers {  
        string name;       // Nombre del receptor
        uint256 tokens;    // Tokens del receptor
    }
  
    mapping(address => Receivers) public users;  // Mapeo de direcciones a datos de usuarios
    
    modifier onlyOwner() {  // Modificador para funciones solo accesibles por el propietario
        require(msg.sender == owner, "Only the owner can perform this action");
        _;
    }
    
    constructor() {
        owner = msg.sender;  // El creador del contrato es el propietario
        users[owner].tokens = 100;  // Inicializa con 100 tokens para el propietario
    }
    
    function double(uint _value) public pure returns (uint) {
        return _value * 2;  // Función para duplicar un valor
    }
    
    function register(string memory _name) public {
        users[msg.sender].name = _name;  // Registrar el nombre de usuario
    }
    
    function giveToken(address _receiver, uint256 _amount) onlyOwner public {
        require(users[owner].tokens >= _amount, "Not enough tokens");
        users[owner].tokens -= _amount;  // Reduce los tokens del propietario
        users[_receiver].tokens += _amount;  // Suma los tokens al receptor
    }

    event OwnerTokens(uint256 tokensAvailable);
    event TokensBought(address buyer, uint256 amount, uint256 value);

    // Función para comprar tokens con Ether
    function buyToken() public payable {
        require(msg.value >= 5 ether, "Insufficient Ether to buy at least 1 token");
        uint256 tokensToBuy = msg.value / 5 ether; // 1 token = 5 Ether
        require(tokensToBuy > 0, "Send enough Ether to purchase at least 1 token");
        require(users[owner].tokens >= tokensToBuy, "Not enough tokens available for sale");

        users[msg.sender].tokens += tokensToBuy;
        users[owner].tokens -= tokensToBuy;

        emit OwnerTokens(users[owner].tokens);
        emit TokensBought(msg.sender, tokensToBuy, msg.value);
    }
    // Retorna el saldo en tokens del usuario
    function balanceOf(address _user) public view returns (uint256 etherBalance, uint256 tokenBalance) {
        etherBalance = address(_user).balance / 1 ether;
        tokenBalance = address(_user).balance / 5 ether; // 1 token = 5 ether    }
    }

    // retorna el saldo en Ether del contrato
    function contractBalances() public view returns (uint256 etherBalance, uint256 tokenBalance) {
        etherBalance = address(this).balance / 1 ether;
        tokenBalance = address(this).balance / 5 ether; // 1 token = 5 ether
    }
    
}
