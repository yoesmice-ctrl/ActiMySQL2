-- =============================================================================
-- TALLER 1 (RETO 1): TRANSFERENCIA BANCARIA SEGURA CON PROCEDIMIENTOS ALMACENADOS
-- Base de datos: BancoDB
-- Temas vistos en clase: procedimientos (IN/OUT), transacciones (START TRANSACTION,
-- COMMIT, ROLLBACK), DECLARE EXIT HANDLER FOR SQLEXCEPTION, SELECT ... FOR UPDATE,
-- auditoría (historial_transferencias).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- PASO 1. Crear la base de datos
-- -----------------------------------------------------------------------------
DROP DATABASE IF EXISTS BancoDB;
CREATE DATABASE BancoDB;
USE BancoDB;
SHOW DATABASES LIKE 'BancoDB';

-- -----------------------------------------------------------------------------
-- PASO 2. Crear las tablas
-- -----------------------------------------------------------------------------
CREATE TABLE cuentas (
    id_cuenta INT PRIMARY KEY,
    titular   VARCHAR(100),
    saldo     DECIMAL(10,2)
);

CREATE TABLE historial_transferencias (
    id_transferencia INT AUTO_INCREMENT PRIMARY KEY,
    cuenta_origen    INT,
    cuenta_destino   INT,
    monto            DECIMAL(10,2),
    fecha            TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

SHOW TABLES;
DESCRIBE cuentas;
DESCRIBE historial_transferencias;

-- -----------------------------------------------------------------------------
-- PASO 3. Insertar datos de prueba
-- -----------------------------------------------------------------------------
INSERT INTO cuentas (id_cuenta, titular, saldo) VALUES
(1, 'Ana López',    5000.00),
(2, 'Carlos Pérez', 3000.00);

SELECT * FROM cuentas;

-- -----------------------------------------------------------------------------
-- PASO 4. Procedimiento TransferirFondos
-- Parámetros: IN p_origen, IN p_destino, IN p_monto, OUT p_codigo_respuesta
-- Códigos: 200 = éxito | 400 = saldo insuficiente | 500 = error de base de datos
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS TransferirFondos;

DELIMITER //

CREATE PROCEDURE TransferirFondos(
    IN  p_origen            INT,
    IN  p_destino           INT,
    IN  p_monto             DECIMAL(10,2),
    OUT p_codigo_respuesta  INT
)
BEGIN
    DECLARE v_saldo_origen DECIMAL(10,2);
    DECLARE v_existe_destino INT;

    -- Manejo de errores: ante cualquier excepción SQL se revierte todo y se retorna 500
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_codigo_respuesta = 500;
    END;

    START TRANSACTION;

    -- Validar saldo: se consulta y se bloquea la fila de la cuenta origen
    SELECT saldo INTO v_saldo_origen
    FROM cuentas
    WHERE id_cuenta = p_origen
    FOR UPDATE;

    -- Se verifica también que la cuenta destino exista (para que el dinero no se pierda)
    SELECT COUNT(*) INTO v_existe_destino
    FROM cuentas
    WHERE id_cuenta = p_destino
    FOR UPDATE;

    IF v_saldo_origen IS NOT NULL
       AND v_existe_destino = 1
       AND v_saldo_origen >= p_monto THEN

        -- 1. Restar saldo a la cuenta origen
        UPDATE cuentas SET saldo = saldo - p_monto WHERE id_cuenta = p_origen;

        -- 2. Sumar saldo a la cuenta destino
        UPDATE cuentas SET saldo = saldo + p_monto WHERE id_cuenta = p_destino;

        -- 3. Registrar la operación en el historial (auditoría)
        INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto)
        VALUES (p_origen, p_destino, p_monto);

        -- 4. Confirmar la transacción
        COMMIT;

        -- 5. Retornar código 200
        SET p_codigo_respuesta = 200;
    ELSE
        -- Saldo insuficiente: se revierte y se retorna 400
        ROLLBACK;
        SET p_codigo_respuesta = 400;
    END IF;
END //

DELIMITER ;

SHOW PROCEDURE STATUS WHERE Db = 'BancoDB';
SHOW CREATE PROCEDURE TransferirFondos;

-- -----------------------------------------------------------------------------
-- PASO 5. Pruebas
-- -----------------------------------------------------------------------------
-- Estado inicial
SELECT * FROM cuentas;

-- Caso exitoso: transferir 1000 de la cuenta 1 a la cuenta 2
CALL TransferirFondos(1, 2, 1000, @codigo);
SELECT @codigo AS codigo_respuesta;   -- Esperado: 200
SELECT * FROM cuentas;                -- Ana: 4000.00 | Carlos: 4000.00

-- Caso fallido: transferir 10000 (saldo insuficiente)
CALL TransferirFondos(1, 2, 10000, @codigo);
SELECT @codigo AS codigo_respuesta;   -- Esperado: 400
SELECT * FROM cuentas;                -- Sin cambios: Ana 4000.00 | Carlos 4000.00

-- Evidencia del registro en auditoría (solo queda la transferencia exitosa)
SELECT * FROM historial_transferencias;
