-- ==============================================================================
-- TALLER 4: OPTIMIZACIÓN DE CONSULTAS Y RENDIMIENTO EN MYSQL (BancoDB)
-- Temas vistos en clase: EXPLAIN ANALYZE, índices, consultas sargables,
-- índices compuestos y cubrientes.
-- ATENCIÓN: este script vuelve a crear las tablas cuentas e historial_transferencias
-- de BancoDB con datos masivos (1.000 cuentas y 10.000 transferencias).
-- Las tablas del Taller 1 se reemplazan (ya tienes sus capturas).
-- ==============================================================================

CREATE DATABASE IF NOT EXISTS BancoDB;
USE BancoDB;

-- ------------------------------------------------------------------------------
-- PARTE 0: ESTRUCTURA DE TABLAS Y POBLAMIENTO DE DATOS MASIVOS
-- ------------------------------------------------------------------------------
-- (auditoria_saldos es del Taller 5 y depende de cuentas: se borra primero para poder
--  repetir este taller sin errores)
DROP TABLE IF EXISTS auditoria_saldos;
DROP TABLE IF EXISTS historial_transferencias;
DROP TABLE IF EXISTS cuentas;

CREATE TABLE cuentas (
    id_cuenta INT PRIMARY KEY AUTO_INCREMENT,
    titular VARCHAR(100) NOT NULL,
    tipo_cuenta VARCHAR(20) NOT NULL DEFAULT 'Ahorros',
    saldo DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    estado VARCHAR(20) NOT NULL DEFAULT 'Activa',
    fecha_apertura DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE historial_transferencias (
    id_transferencia INT AUTO_INCREMENT PRIMARY KEY,
    cuenta_origen INT NOT NULL,
    cuenta_destino INT NOT NULL,
    monto DECIMAL(12, 2) NOT NULL,
    estado_transferencia VARCHAR(20) NOT NULL DEFAULT 'Exitosa',
    fecha DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (cuenta_origen) REFERENCES cuentas(id_cuenta),
    FOREIGN KEY (cuenta_destino) REFERENCES cuentas(id_cuenta)
);

-- Procedimiento auxiliar de carga masiva.
-- Se agrupa todo en UNA transacción (START TRANSACTION / COMMIT) para que la carga
-- sea mucho más rápida que hacer COMMIT automático en cada INSERT.
DROP PROCEDURE IF EXISTS CargarDatosPrueba;
DELIMITER //
CREATE PROCEDURE CargarDatosPrueba()
BEGIN
    DECLARE i INT DEFAULT 1;

    START TRANSACTION;

    -- Insertar 1,000 cuentas
    WHILE i <= 1000 DO
        INSERT INTO cuentas (titular, tipo_cuenta, saldo, estado, fecha_apertura)
        VALUES (
            CONCAT('Cliente_', i),
            IF(i % 2 = 0, 'Ahorros', 'Corriente'),
            ROUND(RAND() * 10000000, 2),
            IF(i % 10 = 0, 'Bloqueada', 'Activa'),
            DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 365) DAY)
        );
        SET i = i + 1;
    END WHILE;

    -- Insertar 10,000 transferencias
    SET i = 1;
    WHILE i <= 10000 DO
        INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto, estado_transferencia, fecha)
        VALUES (
            FLOOR(1 + RAND() * 999),
            FLOOR(1 + RAND() * 999),
            ROUND(1000 + RAND() * 500000, 2),
            IF(i % 15 = 0, 'Fallida', 'Exitosa'),
            DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 180) DAY)
        );
        SET i = i + 1;
    END WHILE;

    COMMIT;
END //
DELIMITER ;

CALL CargarDatosPrueba();
DROP PROCEDURE IF EXISTS CargarDatosPrueba;

-- Verificación de la carga
SELECT COUNT(*) AS total_cuentas FROM cuentas;
SELECT COUNT(*) AS total_transferencias FROM historial_transferencias;
SHOW INDEX FROM historial_transferencias;

-- ==============================================================================
-- PARTE 1: DEMOSTRACIÓN GUIADA (del profesor)
-- ==============================================================================
-- Antes de optimizar: sin índice secundario, MySQL lee toda la tabla
EXPLAIN ANALYZE
SELECT id_transferencia, cuenta_origen, monto, fecha
FROM historial_transferencias
WHERE estado_transferencia = 'Exitosa'
  AND fecha >= '2026-01-01 00:00:00';

-- Índice compuesto
CREATE INDEX idx_transf_estado_fecha ON historial_transferencias(estado_transferencia, fecha);

-- Después de optimizar
EXPLAIN ANALYZE
SELECT id_transferencia, cuenta_origen, monto, fecha
FROM historial_transferencias
WHERE estado_transferencia = 'Exitosa'
  AND fecha >= '2026-01-01 00:00:00';

-- OBSERVACIÓN: los datos se generan con fechas de los últimos 180 días, así que el
-- filtro fecha >= '2026-01-01' lo cumple casi toda la tabla (~93 % de las filas) y
-- MySQL decide que leer la tabla completa sigue siendo más barato que usar el índice.
-- El índice se nota cuando el filtro es SELECTIVO (pocas filas), por ejemplo las
-- transferencias fallidas de los últimos 30 días:
EXPLAIN ANALYZE
SELECT id_transferencia, cuenta_origen, monto, fecha
FROM historial_transferencias
WHERE estado_transferencia = 'Fallida'
  AND fecha >= NOW() - INTERVAL 30 DAY;

-- ==============================================================================
-- PARTE 2: EJERCICIOS
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- EJERCICIO 1: Diagnóstico de "Non-Sargable Query" (función en el WHERE)
-- ------------------------------------------------------------------------------
-- 1.1 Consulta INEFICIENTE: DATE() envuelve la columna fecha
EXPLAIN ANALYZE
SELECT *
FROM historial_transferencias
WHERE DATE(fecha) = '2026-02-15';

-- 1.2 EXPLICACIÓN:
--  a) Al aplicar DATE() sobre la columna, MySQL tiene que calcular DATE(fecha) para
--     CADA fila y recién después compararla; no puede usar el orden del índice, por eso
--     lee toda la tabla ("Table scan").
--  b) Además, el índice idx_transf_estado_fecha tiene primero la columna
--     estado_transferencia y esta consulta no la filtra: sin esa primera columna el
--     índice no sirve para buscar por fecha.
--
-- 1.3 REESCRITURA SARGABLE: comparar la columna "limpia" contra un rango de fechas
EXPLAIN ANALYZE
SELECT *
FROM historial_transferencias
WHERE fecha >= '2026-02-15 00:00:00'
  AND fecha <  '2026-02-16 00:00:00';

-- Aun reescrita, sin un índice que empiece por fecha seguirá leyendo toda la tabla,
-- así que se crea un índice sobre la columna fecha:
CREATE INDEX idx_transf_fecha ON historial_transferencias(fecha);

-- 1.4 COMPARACIÓN FINAL: ahora la versión sargable usa el índice (Index range scan)
EXPLAIN ANALYZE
SELECT *
FROM historial_transferencias
WHERE fecha >= '2026-02-15 00:00:00'
  AND fecha <  '2026-02-16 00:00:00';

-- La versión con DATE(fecha) sigue sin poder usarlo:
EXPLAIN ANALYZE
SELECT *
FROM historial_transferencias
WHERE DATE(fecha) = '2026-02-15';

-- NOTA: los datos se generan con fechas de los últimos 180 días, así que el día
-- '2026-02-15' puede no tener filas. Para ver el mismo efecto con un día que SÍ tiene
-- datos, se repite la comparación con una fecha de hace 30 días:
SET @dia = DATE(NOW() - INTERVAL 30 DAY);
SELECT @dia AS dia_de_prueba;

EXPLAIN ANALYZE
SELECT * FROM historial_transferencias
WHERE DATE(fecha) = @dia;

EXPLAIN ANALYZE
SELECT * FROM historial_transferencias
WHERE fecha >= @dia AND fecha < @dia + INTERVAL 1 DAY;

-- ------------------------------------------------------------------------------
-- EJERCICIO 2: Índice cubriente (Covering Index)
-- ------------------------------------------------------------------------------
-- 2.1 Consulta base (sin índice sobre estado)
EXPLAIN ANALYZE
SELECT titular, saldo, tipo_cuenta
FROM cuentas
WHERE estado = 'Activa';

-- 2.2 SELECT * vs. solo las columnas necesarias:
--  Con SELECT * MySQL debe leer la fila completa de la tabla (todas las columnas) y
--  un índice nunca podría "cubrir" la consulta. Pidiendo solo titular, saldo y
--  tipo_cuenta se mueve menos información y es posible resolver todo desde el índice.
EXPLAIN ANALYZE
SELECT * FROM cuentas WHERE estado = 'Activa';

-- 2.3 Índice cubriente: primero la columna del WHERE (estado) y después las columnas
--     que devuelve el SELECT (titular, saldo, tipo_cuenta)
CREATE INDEX idx_cuentas_cubriente ON cuentas(estado, titular, saldo, tipo_cuenta);

-- 2.4 Verificación: debe aparecer "Covering index lookup" (en EXPLAIN normal: "Using index")
EXPLAIN ANALYZE
SELECT titular, saldo, tipo_cuenta
FROM cuentas
WHERE estado = 'Activa';

EXPLAIN
SELECT titular, saldo, tipo_cuenta
FROM cuentas
WHERE estado = 'Activa';

-- ------------------------------------------------------------------------------
-- EJERCICIO 3: Filtros combinados y JOINs
-- ------------------------------------------------------------------------------
-- 3.1 Consulta base. Se eliminan primero los índices del ejercicio 2 sobre cuentas
--     para ver el punto de partida real del JOIN.
DROP INDEX idx_cuentas_cubriente ON cuentas;

EXPLAIN ANALYZE
SELECT c.id_cuenta, c.titular, ht.id_transferencia, ht.monto, ht.fecha
FROM cuentas c
JOIN historial_transferencias ht ON c.id_cuenta = ht.cuenta_origen
WHERE c.estado = 'Activa'
  AND ht.monto > 300000.00;

-- 3.2 Se revisan los índices existentes (las claves foráneas ya crean índices)
SHOW INDEX FROM historial_transferencias;
SHOW INDEX FROM cuentas;

-- 3.3 Índices propuestos:
--  * historial_transferencias(cuenta_origen, monto): primero la columna del JOIN
--    (igualdad) y después la columna del filtro de rango (monto).
--  * cuentas(estado, id_cuenta): primero la columna con filtro de igualdad (estado).
CREATE INDEX idx_transf_origen_monto ON historial_transferencias(cuenta_origen, monto);
CREATE INDEX idx_cuentas_estado_id ON cuentas(estado, id_cuenta);

-- 3.4 Re-evaluación
EXPLAIN ANALYZE
SELECT c.id_cuenta, c.titular, ht.id_transferencia, ht.monto, ht.fecha
FROM cuentas c
JOIN historial_transferencias ht ON c.id_cuenta = ht.cuenta_origen
WHERE c.estado = 'Activa'
  AND ht.monto > 300000.00;

-- Lista final de índices creados
SHOW INDEX FROM historial_transferencias;
SHOW INDEX FROM cuentas;
