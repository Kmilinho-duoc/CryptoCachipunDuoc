// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//Creación del contrato
contract CriptoCachipun {

    //Creación de la jugada del Cachipún
    enum Jugada {
        Piedra,
        Papel,
        Tijera
    }

    //Creación de los datos que componen al jugador
    struct DatosJugador {
        bytes32 commit;
        uint8 jugada;
        uint256 apuesta;
        bool revelo;
        bool existe;
    }

    //Creación variables para guardar direcciones de wallet de los jugadores
    address public jugador1;
    address public jugador2;

    //Creación de la variable que medirá el tiempo y la del valor de la apuesta
    uint256 public deadline;
    uint256 public apuestaFijada;

    //Creación de la variable para "cerrar" el contrato una vez termine el juego (cambio de estado)
    bool public juegoTerminado;

    mapping(address => DatosJugador) public jugadores;

    event CommitRealizado(address jugador);
    event JugadaRevelada(address jugador, uint8 jugada);
    event Ganador(address ganador, uint256 premio);
    event Empate(uint256 monto);

    modifier soloJugadores() {
        require(
            msg.sender == jugador1 ||
            msg.sender == jugador2,
            "No eres jugador"
        );
        _;
    }

    modifier juegoActivo() {
        require(
            !juegoTerminado,
            "Juego terminado"
        );
        _;
    }

    //Función que permite crear el hash (jugada+secreto) para apostar
    function crearHash(
        uint8 _jugada,
        uint256 _secreto
    )
        public
        pure
        returns(bytes32)
    {
        return keccak256(
            abi.encodePacked(
                _jugada,
                _secreto
            )
        );
    }

    //Función que permite realizar la apuesta (Ether apostado y hash de la jugada)
    function hacerCommit(bytes32 _commit)
        external
        payable
        juegoActivo
    {
        require(
            msg.value > 0,
            "Debes apostar ETH"
        );

        if (jugador1 == address(0)) {
            jugador1 = msg.sender;
            apuestaFijada = msg.value;
        }
        else if (
            jugador2 == address(0) &&
            msg.sender != jugador1
        ) {
            require(msg.value == apuestaFijada, "Debes igualar la apuesta");
            jugador2 = msg.sender;
        }
        else {
            require(
                msg.sender == jugador1 ||
                msg.sender == jugador2,
                "El juego esta lleno"
            );
        }

        require(
            jugadores[msg.sender].commit == bytes32(0),
            "Ya hiciste commit"
        );

        jugadores[msg.sender] = DatosJugador({
            commit: _commit,
            jugada: 0,
            apuesta: msg.value,
            revelo: false,
            existe: true
        });

        if (
            jugadores[jugador1].commit != bytes32(0) &&
            jugadores[jugador2].commit != bytes32(0)
        ) {
            deadline = block.timestamp + 5 minutes;
        }

        emit CommitRealizado(msg.sender);
    }

    function revelarJugada(
        uint8 _jugada,
        uint256 _secreto
    )
        external
        soloJugadores
        juegoActivo
    {
        require(
            jugador1 != address(0) &&
            jugador2 != address(0),
            "Faltan jugadores"
        );
        require(
            block.timestamp <= deadline,
            "Tiempo agotado"
        );
        require(
            !jugadores[msg.sender].revelo,
            "Ya revelaste"
        );
        require(
            _jugada <= 2,
            "Jugada invalida"
        );

        bytes32 hashVerificar =
            keccak256(
                abi.encodePacked(
                    _jugada,
                    _secreto
                )
            );

        require(
            hashVerificar == jugadores[msg.sender].commit,
            "Hash incorrecto"
        );

        jugadores[msg.sender].jugada = _jugada;
        jugadores[msg.sender].revelo = true;

        emit JugadaRevelada(msg.sender, _jugada);

        if (
            jugadores[jugador1].revelo &&
            jugadores[jugador2].revelo
        ) {
            determinarGanador();
        }
    }

    //Función que determina quien es el ganador del juego
    function determinarGanador()
        internal
    {
        juegoTerminado = true;
        uint8 j1 = jugadores[jugador1].jugada;
        uint8 j2 = jugadores[jugador2].jugada;

        uint256 premio = address(this).balance;

        /*
        Se evalua primero si ambas manos son iguales para así decidir el empate y devolver las cantidades apostadas a sus jugadores
        */

        if (j1 == j2) {
            uint256 mitad = premio / 2;

            (bool exito1, ) = payable(jugador1).call{value: mitad}("");
            (bool exito2, ) = payable(jugador2).call{value: mitad}("");
            require(exito1 && exito2, "Fallo transferencia");

            emit Empate(mitad);
            return;
        }

        /*
        Si ambas manos no son iguales entonces se limita exclusivamente a dos casos únicos: o gana el jugador 1 o gana el jugador 2
        */

        address ganador;
        if ((j1 + 3 - j2) % 3 == 1) {
            ganador = jugador1;
        } else {
            ganador = jugador2;
        }

        (bool exitoGanador, ) = payable(ganador).call{value: premio}("");
        require(exitoGanador, "Fallo transferencia");

        emit Ganador(ganador, premio);
    }

    //Función para reclamar que el tiempo ha terminado (para evitar el caso de un solo "reveal")
    function reclamarTimeout()
        external
        juegoActivo
    {
        require(
            block.timestamp > deadline,
            "Aun no termina el tiempo"
        );

        bool j1Revelo = jugadores[jugador1].revelo;
        bool j2Revelo = jugadores[jugador2].revelo;

        juegoTerminado = true;
        uint256 premio = address(this).balance;

        if (j1Revelo && !j2Revelo) {
            (bool exito, ) = payable(jugador1).call{value: premio}("");
            require(exito, "Fallo transferencia");
            emit Ganador(jugador1, premio);
        }
        else if (!j1Revelo && j2Revelo) {
            (bool exito, ) = payable(jugador2).call{value: premio}("");
            require(exito, "Fallo transferencia");
            emit Ganador(jugador2, premio);
        }
        else {
            uint256 mitad = premio / 2;
            (bool exito1, ) = payable(jugador1).call{value: mitad}("");
            (bool exito2, ) = payable(jugador2).call{value: mitad}("");
            require(exito1 && exito2, "Fallo transferencia");

            emit Empate(mitad);
        }
    }
}