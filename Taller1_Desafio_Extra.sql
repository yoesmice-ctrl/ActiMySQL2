-- =============================================================================
-- TALLER 1 - DESAFÍO EXTRA (OPCIONAL)
-- Ejecutar DESPUÉS de Taller1_Transferencia_Segura.sql
-- Cambios sobre el procedimiento original (se crea como TransferirFondosV2 para
-- no perder el original):
--   * Validar que el monto sea mayor que cero -> código 401
--   * Parámetro OUT adicional con el nombre del titular de la cuenta origen
--   * Registrar el usuario responsable de la operación
-- =============================================================================
USE BancoDB;

-- Nueva columna para guardar el usuario responsable en la auditoría
ALTER TABLE historial_transferencias ADD COLUMN usuario VARCHAR(100);
DESCRIBE historial_transferencias;

DROP PROCEDURE IF EXISTS TransferirFondosV2;

DELIMITER //

CREATE PROCEDURE TransferirFondosV2(
    IN  p_origen              INT,
    IN  p_destino             INT,
    IN  p_monto               DECIMAL(10,2),
    OUT p_codigo_respuesta    INT,
    OUT p_titular_origen      VARCHAR(100)
)
BEGIN
    DECLARE v_saldo_origen   DECIMAL(10,2);
    DECLARE v_existe_destino INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_codigo_respuesta = 500;
    END;

    SET p_titular_origen = NULL;

    IF p_monto <= 0 THEN
        -- Monto inválido: no se inicia la transacción
        SET p_codigo_respuesta = 401;
    ELSE
        START TRANSACTION;

        SELECT saldo, titular INTO v_saldo_origen, p_titular_origen
        FROM cuentas
        WHERE id_cuenta = p_origen
        FOR UPDATE;

        SELECT COUNT(*) INTO v_existe_destino
        FROM cuentas
        WHERE id_cuenta = p_destino
        FOR UPDATE;

        IF v_saldo_origen IS NOT NULL
           AND v_existe_destino = 1
           AND v_saldo_origen >= p_monto THEN

            UPDATE cuentas SET saldo = saldo - p_monto WHERE id_cuenta = p_origen;
            UPDATE cuentas SET saldo = saldo + p_monto WHERE id_cuenta = p_destino;

            -- Se registra también el usuario responsable de la operación
            INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto, usuario)
            VALUES (p_origen, p_destino, p_monto, USER());

            COMMIT;
            SET p_codigo_respuesta = 200;
        ELSE
            ROLLBACK;
            SET p_codigo_respuesta = 400;
        END IF;
    END IF;
END //

DELIMITER ;

-- Pruebas
SELECT * FROM cuentas;

-- Monto inválido (cero o negativo) -> 401
CALL TransferirFondosV2(1, 2, 0, @codigo, @titular);
SELECT @codigo AS codigo_respuesta, @titular AS titular_origen;

CALL TransferirFondosV2(1, 2, -50, @codigo, @titular);
SELECT @codigo AS codigo_respuesta, @titular AS titular_origen;

-- Transferencia exitosa -> 200 y nombre del titular origen
CALL TransferirFondosV2(1, 2, 500, @codigo, @titular);
SELECT @codigo AS codigo_respuesta, @titular AS titular_origen;

-- Saldo insuficiente -> 400
CALL TransferirFondosV2(1, 2, 10000, @codigo, @titular);
SELECT @codigo AS codigo_respuesta, @titular AS titular_origen;

SELECT * FROM cuentas;
SELECT * FROM historial_transferencias;   -- La columna usuario muestra quién ejecutó
