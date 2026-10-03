-- ============================================================================
-- TALLER 3: SEGURIDAD, PERMISOS Y PREVENCIÓN DE SQL INJECTION EN MYSQL
-- Dominio: Sistema Bancario (BancoBD)
-- Temas vistos en clase: CREATE USER ('usuario'@'host'), GRANT en distintos niveles
-- (base de datos, tabla, columna), REVOKE, SHOW GRANTS, principio de menor privilegio,
-- sentencias preparadas (PREPARE / EXECUTE / DEALLOCATE) contra SQL Injection.
-- Se ejecuta como ROOT (o administrador). La Parte B se ejecuta desde la terminal
-- con cada usuario (ver instrucciones en los comentarios).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PASO 0: Preparación del entorno
-- ----------------------------------------------------------------------------
DROP DATABASE IF EXISTS BancoBD;
CREATE DATABASE BancoBD;
USE BancoBD;

CREATE TABLE cuentas (
    id_cuenta INT PRIMARY KEY AUTO_INCREMENT,
    titular   VARCHAR(100) NOT NULL,
    saldo     DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    estado    VARCHAR(20) DEFAULT 'Activa'
);

CREATE TABLE historial_transferencias (
    id_transferencia INT AUTO_INCREMENT PRIMARY KEY,
    cuenta_origen    INT NOT NULL,
    cuenta_destino   INT NOT NULL,
    monto            DECIMAL(10,2) NOT NULL,
    fecha            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (cuenta_origen)  REFERENCES cuentas(id_cuenta),
    FOREIGN KEY (cuenta_destino) REFERENCES cuentas(id_cuenta)
);

INSERT INTO cuentas (titular, saldo, estado) VALUES
('Carlos Mendoza', 2500000.00, 'Activa'),
('Ana Gómez',       850000.00, 'Activa'),
('Roberto Silva',   120000.00, 'Bloqueada');

INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto) VALUES
(1, 2, 100000.00);

SHOW TABLES;
SELECT * FROM cuentas;

-- ----------------------------------------------------------------------------
-- PASO 1: Higiene de seguridad - limpieza de usuarios anónimos
-- ----------------------------------------------------------------------------
DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'%';

-- Evidencia: no deben quedar usuarios con nombre vacío
SELECT user, host FROM mysql.user ORDER BY user;

-- ----------------------------------------------------------------------------
-- PASO 2: Creación de usuarios por roles ('usuario'@'host')
-- (CREATE USER solo crea la identidad: todavía NO tienen ningún permiso)
-- ----------------------------------------------------------------------------
DROP USER IF EXISTS 'admin_banco'@'localhost';
DROP USER IF EXISTS 'cajero_app'@'localhost';
DROP USER IF EXISTS 'auditor_consulta'@'%';
DROP USER IF EXISTS 'app_backend'@'localhost';

-- 1. Administrador local
CREATE USER 'admin_banco'@'localhost' IDENTIFIED BY 'AdminBank2026!#';
-- 2. Cajero (acceso restringido)
CREATE USER 'cajero_app'@'localhost' IDENTIFIED BY 'CajeroPass2026!';
-- 3. Auditor (acceso remoto de consulta)
CREATE USER 'auditor_consulta'@'%' IDENTIFIED BY 'AuditorPass2026!';
-- 4. Aplicación backend
CREATE USER 'app_backend'@'localhost' IDENTIFIED BY 'AppBackend2026!Sec';

SELECT user, host FROM mysql.user
WHERE user IN ('admin_banco','cajero_app','auditor_consulta','app_backend');

-- Antes de dar permisos: solo tienen USAGE (sin privilegios)
SHOW GRANTS FOR 'cajero_app'@'localhost';

-- ----------------------------------------------------------------------------
-- PASO 3: Asignación granular de privilegios (GRANT) - menor privilegio
-- ----------------------------------------------------------------------------
-- A) Administrador: privilegios totales sobre la base de datos del banco
GRANT ALL PRIVILEGES ON BancoBD.* TO 'admin_banco'@'localhost' WITH GRANT OPTION;

-- B) Aplicación backend: operaciones DML (lectura, inserción y actualización)
GRANT SELECT, INSERT, UPDATE ON BancoBD.* TO 'app_backend'@'localhost';

-- C) Cajero: restringido a columnas específicas de la tabla cuentas
--    Solo puede ver id_cuenta, titular y saldo, y actualizar saldo
GRANT SELECT (id_cuenta, titular, saldo), UPDATE (saldo) ON BancoBD.cuentas TO 'cajero_app'@'localhost';

-- D) Auditor: solo lectura sobre todo el esquema
GRANT SELECT ON BancoBD.* TO 'auditor_consulta'@'%';

-- En MySQL 8.0 GRANT y REVOKE se aplican de inmediato: no hace falta FLUSH PRIVILEGES
-- (solo se usaría si se modificaran a mano las tablas del sistema, lo cual es un anti-patrón).

-- ----------------------------------------------------------------------------
-- PASO 4: Verificación y revocación de privilegios (SHOW GRANTS y REVOKE)
-- ----------------------------------------------------------------------------
SHOW GRANTS FOR 'admin_banco'@'localhost';
SHOW GRANTS FOR 'cajero_app'@'localhost';
SHOW GRANTS FOR 'app_backend'@'localhost';
SHOW GRANTS FOR 'auditor_consulta'@'%';

-- >>> PARTE B (terminal, ANTES del REVOKE): probar al cajero <<<
--   mysql -u cajero_app -p            (clave: CajeroPass2026!)
--   USE BancoBD;
--   SELECT id_cuenta, titular, saldo FROM cuentas;            -- permitido
--   SELECT estado FROM cuentas;                               -- ERROR 1143 (columna sin permiso)
--   SELECT * FROM historial_transferencias;                   -- ERROR 1142 (tabla sin permiso)
--   UPDATE cuentas SET saldo = saldo + 1000 WHERE id_cuenta = 2;  -- permitido (aún tiene UPDATE(saldo))

-- Revocar el permiso de actualización al cajero.
-- OJO: el UPDATE se había concedido sobre la COLUMNA saldo, por eso se revoca con la columna.
REVOKE UPDATE (saldo) ON BancoBD.cuentas FROM 'cajero_app'@'localhost';

SHOW GRANTS FOR 'cajero_app'@'localhost';   -- Ahora solo conserva SELECT (id_cuenta, titular, saldo)

-- >>> PARTE B (terminal, DESPUÉS del REVOKE) <<<
--   UPDATE cuentas SET saldo = saldo + 1000 WHERE id_cuenta = 2;  -- ERROR 1143 (UPDATE denied)
--
-- >>> Probar a los demás usuarios <<<
--   mysql -u app_backend -p           (clave: AppBackend2026!Sec)
--   DELETE FROM BancoBD.cuentas WHERE id_cuenta = 3;           -- ERROR 1142 (no tiene DELETE)
--   mysql -u auditor_consulta -p      (clave: AuditorPass2026!)
--   SELECT * FROM BancoBD.cuentas;                             -- permitido
--   INSERT INTO BancoBD.cuentas (titular) VALUES ('X');        -- ERROR 1142 (solo lectura)

-- ----------------------------------------------------------------------------
-- PASO 5: Prevención de SQL Injection con sentencias preparadas (PREPARE)
-- ----------------------------------------------------------------------------
USE BancoBD;

-- 5.1 Sentencia preparada con marcadores de posición '?'
PREPARE stmt_buscar_cuenta FROM
'SELECT id_cuenta, titular, saldo, estado FROM cuentas WHERE id_cuenta = ? AND estado = ?';

SET @id_busqueda = 1;
SET @estado_busqueda = 'Activa';

EXECUTE stmt_buscar_cuenta USING @id_busqueda, @estado_busqueda;

DEALLOCATE PREPARE stmt_buscar_cuenta;

-- 5.2 Demostración del ataque: consulta construida CONCATENANDO el input (vulnerable)
SET @entrada = "x' OR '1'='1";
SET @sql_vulnerable = CONCAT("SELECT id_cuenta, titular, saldo FROM cuentas WHERE titular = '", @entrada, "'");
SELECT @sql_vulnerable AS consulta_construida;

PREPARE stmt_vulnerable FROM @sql_vulnerable;
EXECUTE stmt_vulnerable;            -- Devuelve TODAS las cuentas (el input reescribió la consulta)
DEALLOCATE PREPARE stmt_vulnerable;

-- 5.3 La defensa: el mismo input, pero como parámetro '?' (seguro)
PREPARE stmt_seguro FROM
'SELECT id_cuenta, titular, saldo FROM cuentas WHERE titular = ?';

EXECUTE stmt_seguro USING @entrada; -- Devuelve 0 filas: el input se trata solo como dato
DEALLOCATE PREPARE stmt_seguro;

-- Con un titular real la consulta segura sí devuelve el resultado esperado
SET @entrada_valida = 'Ana Gómez';
PREPARE stmt_seguro FROM
'SELECT id_cuenta, titular, saldo FROM cuentas WHERE titular = ?';
EXECUTE stmt_seguro USING @entrada_valida;
DEALLOCATE PREPARE stmt_seguro;
