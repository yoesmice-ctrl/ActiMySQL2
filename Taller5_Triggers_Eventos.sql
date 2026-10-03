-- ==============================================================================
-- TALLER 5: TRIGGERS Y EVENTOS EN MYSQL (BancoDB)
-- Temas vistos en clase: triggers BEFORE/AFTER, FOR EACH ROW, pseudo-registros
-- OLD y NEW, SIGNAL SQLSTATE '45000', eventos (event_scheduler, EVERY, STARTS,
-- ON COMPLETION PRESERVE), SHOW EVENTS e information_schema.EVENTS.
-- REQUISITO: ejecutar DESPUÉS del Taller 4 (usa cuentas con la columna estado y
-- la tabla historial_transferencias de BancoDB).
-- ==============================================================================

USE BancoDB;

-- ------------------------------------------------------------------------------
-- PARTE 0: TABLAS DE AUDITORÍA Y MÉTRICAS (estructura de soporte)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auditoria_saldos (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_cuenta INT NOT NULL,
    saldo_anterior DECIMAL(10,2) NOT NULL,
    saldo_nuevo DECIMAL(10,2) NOT NULL,
    usuario VARCHAR(100) NOT NULL,
    fecha_modificacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_cuenta) REFERENCES cuentas(id_cuenta)
);

CREATE TABLE IF NOT EXISTS metricas_diarias (
    id_metrica INT AUTO_INCREMENT PRIMARY KEY,
    fecha_metrica DATE NOT NULL,
    total_cuentas INT NOT NULL,
    saldo_total_sistema DECIMAL(12,2) NOT NULL,
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Encender el programador de eventos (requiere usuario administrador, p. ej. root)
SET GLOBAL event_scheduler = ON;
SHOW VARIABLES LIKE 'event_scheduler';

SHOW TABLES;

-- ==============================================================================
-- PARTE 1: DEMOSTRACIÓN GUIADA
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1.1 TRIGGER: auditoría automática de cambios de saldo (AFTER UPDATE)
-- ------------------------------------------------------------------------------
DELIMITER //

DROP TRIGGER IF EXISTS trg_auditar_cambio_saldo //

CREATE TRIGGER trg_auditar_cambio_saldo
AFTER UPDATE ON cuentas
FOR EACH ROW
BEGIN
    -- Solo registra si el saldo realmente cambió
    IF OLD.saldo <> NEW.saldo THEN
        INSERT INTO auditoria_saldos (id_cuenta, saldo_anterior, saldo_nuevo, usuario)
        VALUES (NEW.id_cuenta, OLD.saldo, NEW.saldo, USER());
    END IF;
END //

DELIMITER ;

-- Prueba: modificar el saldo de la cuenta 1 y revisar la auditoría
SELECT id_cuenta, titular, saldo FROM cuentas WHERE id_cuenta = 1;
UPDATE cuentas SET saldo = saldo + 500.00 WHERE id_cuenta = 1;
SELECT * FROM auditoria_saldos;

-- ------------------------------------------------------------------------------
-- 1.2 EVENTO: resumen periódico de métricas (EVERY 1 DAY)
-- ------------------------------------------------------------------------------
DELIMITER //

DROP EVENT IF EXISTS evt_registrar_metricas_diarias //

CREATE EVENT evt_registrar_metricas_diarias
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Consolida el saldo total y cantidad de cuentas activas diariamente'
DO
BEGIN
    INSERT INTO metricas_diarias (fecha_metrica, total_cuentas, saldo_total_sistema)
    SELECT CURDATE(), COUNT(id_cuenta), IFNULL(SUM(saldo), 0.00)
    FROM cuentas
    WHERE estado = 'Activa';
END //

DELIMITER ;

-- Como el evento arranca en CURRENT_TIMESTAMP, se ejecuta casi de inmediato.
SELECT SLEEP(2);
SHOW EVENTS FROM BancoDB;
SELECT * FROM metricas_diarias;

-- ==============================================================================
-- PARTE 2: EJERCICIOS
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- EJERCICIO 1 (TRIGGER): validación de transferencias (BEFORE INSERT)
-- Reglas: monto > 0 y cuenta_origen <> cuenta_destino; si no se cumplen,
-- abortar con SIGNAL SQLSTATE '45000'.
-- ------------------------------------------------------------------------------
DELIMITER //

DROP TRIGGER IF EXISTS trg_validar_transferencia //

CREATE TRIGGER trg_validar_transferencia
BEFORE INSERT ON historial_transferencias
FOR EACH ROW
BEGIN
    IF NEW.monto <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El monto de la transferencia debe ser mayor a cero';
    END IF;

    IF NEW.cuenta_origen = NEW.cuenta_destino THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La cuenta de origen y destino no pueden ser iguales';
    END IF;
END //

DELIMITER ;

SHOW TRIGGERS FROM BancoDB;

-- Pruebas del trigger
SELECT COUNT(*) AS transferencias_antes FROM historial_transferencias;

-- Las 3 inserciones siguientes DEBEN FALLAR a propósito. Están comentadas para que
-- "source" no se detenga en el primer error. Ejecútalas a mano, una por una, en el
-- prompt mysql> y toma la captura de cada mensaje de error:
--
-- a) Monto igual a cero  -> ERROR 1644 (45000): El monto de la transferencia debe ser mayor a cero
--    INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto) VALUES (1, 2, 0);
--
-- b) Monto negativo      -> ERROR 1644 (45000): El monto de la transferencia debe ser mayor a cero
--    INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto) VALUES (1, 2, -100);
--
-- c) Misma cuenta        -> ERROR 1644 (45000): La cuenta de origen y destino no pueden ser iguales
--    INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto) VALUES (3, 3, 1000);

-- d) Transferencia válida (esta sí se inserta)
INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto)
VALUES (1, 2, 2500);

SELECT COUNT(*) AS transferencias_despues FROM historial_transferencias;   -- +1 (solo la válida)
SELECT * FROM historial_transferencias ORDER BY id_transferencia DESC LIMIT 3;

-- ------------------------------------------------------------------------------
-- EJERCICIO 2 (EVENTO): inactivación automática de cuentas en cero
-- Cada día, las cuentas 'Activa' con saldo 0.00 pasan a 'Inactiva'.
-- ------------------------------------------------------------------------------
-- Datos de prueba: dos cuentas activas con saldo 0 y una con saldo > 0
INSERT INTO cuentas (titular, tipo_cuenta, saldo, estado)
VALUES ('Prueba_Cero_1', 'Ahorros',   0.00, 'Activa'),
       ('Prueba_Cero_2', 'Corriente', 0.00, 'Activa'),
       ('Prueba_Con_Saldo', 'Ahorros', 100.00, 'Activa');

SELECT id_cuenta, titular, saldo, estado FROM cuentas WHERE titular LIKE 'Prueba%';

DELIMITER //

DROP EVENT IF EXISTS evt_inactivar_cuentas_vacias //

CREATE EVENT evt_inactivar_cuentas_vacias
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Cambia a Inactiva las cuentas activas con saldo igual a cero'
DO
BEGIN
    UPDATE cuentas
    SET estado = 'Inactiva'
    WHERE saldo = 0.00
      AND estado = 'Activa';
END //

DELIMITER ;

-- El evento arranca de inmediato; se espera un momento y se verifica
SELECT SLEEP(2);

SELECT id_cuenta, titular, saldo, estado FROM cuentas WHERE titular LIKE 'Prueba%';

-- Inspección del evento en el diccionario de datos
SHOW EVENTS FROM BancoDB;
SELECT EVENT_NAME, STATUS, EVENT_TYPE, INTERVAL_VALUE, INTERVAL_FIELD, LAST_EXECUTED
FROM information_schema.EVENTS
WHERE EVENT_SCHEMA = 'BancoDB';
