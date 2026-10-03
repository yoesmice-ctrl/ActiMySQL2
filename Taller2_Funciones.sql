-- =============================================================================
-- TALLER 2: FUNCIONES DEFINIDAS POR EL USUARIO (MYSQL)
-- Dominio: Sistema Bancario ("BancoTaller")
-- Temas vistos en clase: CREATE FUNCTION, RETURNS, DETERMINISTIC / NOT DETERMINISTIC,
-- READS SQL DATA, IF / ELSEIF, WHILE, DELIMITER.
-- Nota: las funciones del taller consultan las tablas Cuentas y Transacciones
-- (con cuenta_id), por eso se trabaja en una base propia (BancoTaller) para no
-- mezclarlas con las tablas de BancoDB (que usan id_cuenta).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- PASO 0. Base de datos, tablas y datos de prueba
-- -----------------------------------------------------------------------------
DROP DATABASE IF EXISTS BancoTaller;
CREATE DATABASE BancoTaller;
USE BancoTaller;

CREATE TABLE Cuentas (
    cuenta_id INT PRIMARY KEY AUTO_INCREMENT,
    titular   VARCHAR(100) NOT NULL,
    saldo     DECIMAL(12,2) NOT NULL DEFAULT 0.00
);

CREATE TABLE Transacciones (
    transaccion_id   INT PRIMARY KEY AUTO_INCREMENT,
    cuenta_id        INT NOT NULL,
    tipo_transaccion VARCHAR(20) NOT NULL,      -- 'Retiro' o 'Deposito'
    monto            DECIMAL(12,2) NOT NULL,
    fecha            DATETIME NOT NULL,
    FOREIGN KEY (cuenta_id) REFERENCES Cuentas(cuenta_id)
);

INSERT INTO Cuentas (titular, saldo) VALUES
('Carlos Mendoza', 2500000.00),   -- cuenta 1
('Ana Gómez',       850000.00),   -- cuenta 2
('Roberto Silva',   120000.00),   -- cuenta 3
('Laura Torres',   3000000.00);   -- cuenta 4

INSERT INTO Transacciones (cuenta_id, tipo_transaccion, monto, fecha) VALUES
(1, 'Retiro',   200000.00, '2026-01-05 10:00:00'),
(1, 'Retiro',   350000.00, '2026-01-20 15:30:00'),
(1, 'Deposito', 900000.00, '2026-01-25 09:00:00'),
(1, 'Retiro',   150000.00, '2026-02-03 11:00:00'),
(2, 'Retiro',    80000.00, '2026-01-10 08:45:00'),
(2, 'Deposito', 400000.00, '2026-01-12 12:00:00'),
(3, 'Retiro',    50000.00, '2026-01-15 17:00:00'),
(4, 'Retiro',  7500000.00, '2026-01-18 13:00:00'),   -- retiros mayores a 2 x saldo
(4, 'Retiro',  1000000.00, '2026-02-10 14:00:00');

SELECT * FROM Cuentas;
SELECT * FROM Transacciones;

-- -----------------------------------------------------------------------------
-- EJERCICIO 1: Cálculo del Impuesto 4x1000 (GMF)
-- Característica: DETERMINISTIC (no consulta tablas, cálculo matemático directo)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS CalcularImpuestoGMF;

DELIMITER //

CREATE FUNCTION CalcularImpuestoGMF(
    p_monto DECIMAL(12,2),
    p_es_exenta BOOLEAN
)
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    DECLARE v_impuesto DECIMAL(12,2);

    IF p_es_exenta THEN
        SET v_impuesto = 0.00;
    ELSE
        -- 4x1000 equivale al 0.4% (monto * 0.004)
        SET v_impuesto = p_monto * 0.004;
    END IF;

    RETURN v_impuesto;
END //

DELIMITER ;

-- Pruebas Ejercicio 1
SELECT CalcularImpuestoGMF(1000000.00, FALSE) AS Impuesto_4x1000;   -- 4000.00
SELECT CalcularImpuestoGMF(1000000.00, TRUE)  AS Impuesto_Exento;   -- 0.00

-- -----------------------------------------------------------------------------
-- EJERCICIO 2: Total de retiros en un rango de fechas
-- Característica: READS SQL DATA (consulta la tabla Transacciones)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS ObtenerTotalRetirosPeriodo;

DELIMITER //

CREATE FUNCTION ObtenerTotalRetirosPeriodo(
    p_cuenta_id INT,
    p_fecha_inicio DATE,
    p_fecha_fin DATE
)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_total_retiros DECIMAL(12,2);

    SELECT IFNULL(SUM(monto), 0.00)
    INTO v_total_retiros
    FROM Transacciones
    WHERE cuenta_id = p_cuenta_id
      AND tipo_transaccion = 'Retiro'
      AND DATE(fecha) BETWEEN p_fecha_inicio AND p_fecha_fin;

    RETURN v_total_retiros;
END //

DELIMITER ;

-- Pruebas Ejercicio 2
SELECT ObtenerTotalRetirosPeriodo(1, '2026-01-01', '2026-01-31') AS Total_Retiros_Enero;   -- 550000.00
SELECT ObtenerTotalRetirosPeriodo(3, '2026-02-01', '2026-02-28') AS Sin_Retiros;           -- 0.00

-- -----------------------------------------------------------------------------
-- EJERCICIO 3: Proyección de rendimientos de un CDT con bucle (WHILE)
-- Característica: DETERMINISTIC (interés compuesto con estructura iterativa)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS ProyectarRendimientoCDT;

DELIMITER //

CREATE FUNCTION ProyectarRendimientoCDT(
    p_capital DECIMAL(12,2),
    p_tasa_anual DECIMAL(5,2),
    p_anios INT
)
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    DECLARE v_capital_acumulado DECIMAL(12,2);
    DECLARE v_contador INT DEFAULT 1;

    SET v_capital_acumulado = p_capital;

    WHILE v_contador <= p_anios DO
        SET v_capital_acumulado = v_capital_acumulado * (1 + (p_tasa_anual / 100.0));
        SET v_contador = v_contador + 1;
    END WHILE;

    RETURN v_capital_acumulado;
END //

DELIMITER ;

-- Pruebas Ejercicio 3
SELECT ProyectarRendimientoCDT(10000000.00, 10.50, 3) AS Capital_Proyectado_3Anios;

-- -----------------------------------------------------------------------------
-- EJERCICIO 4: Evaluación de elegibilidad de crédito (reto integrador)
-- Característica: READS SQL DATA (consulta saldo y retiros y aplica reglas)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS EvaluarElegibilidadCredito;

DELIMITER //

CREATE FUNCTION EvaluarElegibilidadCredito(
    p_cuenta_id INT
)
RETURNS VARCHAR(30)
READS SQL DATA
BEGIN
    DECLARE v_saldo DECIMAL(12,2);
    DECLARE v_total_retiros DECIMAL(12,2);
    DECLARE v_resultado VARCHAR(30);

    -- Saldo actual de la cuenta
    SELECT saldo INTO v_saldo
    FROM Cuentas
    WHERE cuenta_id = p_cuenta_id;

    -- Si la cuenta no existe en el sistema
    IF v_saldo IS NULL THEN
        RETURN 'Cuenta Inexistente';
    END IF;

    -- Total histórico de retiros
    SELECT IFNULL(SUM(monto), 0.00)
    INTO v_total_retiros
    FROM Transacciones
    WHERE cuenta_id = p_cuenta_id
      AND tipo_transaccion = 'Retiro';

    -- Reglas de negocio
    IF v_saldo >= 2000000.00 AND v_total_retiros <= (v_saldo * 2) THEN
        SET v_resultado = 'Aprobado';
    ELSEIF v_saldo >= 500000.00 AND v_saldo < 2000000.00 THEN
        SET v_resultado = 'Requiere Aval';
    ELSE
        SET v_resultado = 'Rechazado';
    END IF;

    RETURN v_resultado;
END //

DELIMITER ;

-- Pruebas Ejercicio 4
SELECT cuenta_id, titular, saldo, EvaluarElegibilidadCredito(cuenta_id) AS Estado_Credito
FROM Cuentas;
SELECT EvaluarElegibilidadCredito(99) AS Cuenta_Inexistente;

-- Verificación de las funciones creadas
SHOW FUNCTION STATUS WHERE Db = 'BancoTaller';
