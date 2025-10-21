// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.5.0 <0.9.0;

/*
  Librería para operaciones sobre el mapping de balances.
  Se declara como librería para reutilizar la lógica de mover tokens
  entre cuentas sin repetir código en el contrato principal.
*/
library Balances {
    // Nota: el primer parámetro es `mapping(address => uint256) storage balances`
    // lo que indica que la función opera sobre el mapping almacenado en storage
    // del contrato que la invoque.
    function move(mapping(address => uint256) storage balances, address from, address to, uint amount) internal {
        // Comprobar que 'from' tiene saldo suficiente
        require(balances[from] >= amount);
        // Comprobación simple de overflow al sumar: garantiza que balances[to] + amount
        // no envuelva y sea menor que balances[to] (protección para versiones <0.8.0).
        require(balances[to] + amount >= balances[to]);
        // Restar del emisor
        balances[from] -= amount;
        // Añadir al receptor
        balances[to] += amount;
    }
}

/*
  Contrato Token simple (similar a ERC-20 básico).
  - mapping balances: saldo por dirección
  - allowed: allowance [owner][spender] => cantidad permitida
  - usa la librería Balances para mover tokens
*/
contract Token {
    // Saldo por dirección (almacenado en el contrato)
    mapping(address => uint256) balances;

    // Indica que las funciones de la librería Balances están disponibles.
    // `using Balances for *;` permite usar las funciones de la librería
    // con el mapping como receptor (aunque convención más común es usar `using Balances for mapping(address => uint256);`)
    using Balances for *;

    // allowed[owner][spender] = tokens (permite que `spender` gaste en nombre de `owner`)
    mapping(address => mapping(address => uint256)) allowed;

    // Eventos para notificar transferencias y aprobaciones (útiles para indexar/monitorizar fuera de la cadena)
    event Transfer(address from, address to, uint amount);
    event Approval(address owner, address spender, uint amount);

    /*
      transfer: mueve tokens desde msg.sender hacia `to`.
      - llama a balances.move (librería) que hace las comprobaciones y modifica los balances.
      - emite evento Transfer.
    */
    function transfer(address to, uint amount) external returns (bool success) {
        // mueve saldo de msg.sender a `to`
        balances.move(msg.sender, to, amount);
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function giveMe(uint amount) external {
        balances[msg.sender] += amount;
    }

    /*
      transferFrom: permite a `msg.sender` transferir tokens desde `from` hacia `to`
      si previamente `from` ha aprobado a msg.sender la cantidad suficiente.
    */
    function transferFrom(address from, address to, uint amount) external returns (bool success) {
        // comprobar allowance
        require(allowed[from][msg.sender] >= amount);
        // decrementar allowance
        allowed[from][msg.sender] -= amount;
        // mover los fondos
        balances.move(from, to, amount);
        emit Transfer(from, to, amount);
        return true;
    }

    /*
      approve: owner aprueba a `spender` para gastar `tokens` en su nombre.
      Observación: aquí se exige que la allowance previa sea 0 antes de establecer una nueva.
      Esto es una protección contra la condición de carrera conocida de `approve`:
      - Si no se obliga a poner a 0 antes, un spender podría gastar la cantidad antigua y la nueva.
      - Requisito: allowed[msg.sender][spender] == 0
    */
    function approve(address spender, uint tokens) external returns (bool success) {
        require(allowed[msg.sender][spender] == 0, "");
        allowed[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);
        return true;
    }

    // Devuelve el saldo de una dirección
    function balanceOf(address tokenOwner) external view returns (uint balance) {
        return balances[tokenOwner];
    }
}
