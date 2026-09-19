-- 1. Crear tabla 'cuenta'
CREATE TABLE cuenta (
    cuenta_id INT PRIMARY KEY,
    titular VARCHAR(100) NOT NULL,
    tipo_cuenta VARCHAR(50) NOT NULL,
    saldo DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    fecha_apertura DATE DEFAULT (CURRENT_DATE)
);

-- 2. Crear tabla 'transaccion'
CREATE TABLE transaccion (
    transaccion_id INT PRIMARY KEY,
    cuenta_id INT NOT NULL,
    tipo_transaccion VARCHAR(20) NOT NULL,
    monto DECIMAL(12,2) NOT NULL,
    fecha_transaccion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_cuenta FOREIGN KEY (cuenta_id) REFERENCES cuenta(cuenta_id) ON DELETE CASCADE
);

-- 3. Insertar datos de prueba en 'cuenta'
INSERT INTO cuenta (cuenta_id, titular, tipo_cuenta, saldo) VALUES
(1, 'Carlos Mendoza', 'Ahorros', 1500.50),
(2, 'Ana Gómez', 'Corriente', 3200.00),
(3, 'Luis Torres', 'Ahorros', 450.75);

-- 4. Insertar datos de prueba en 'transaccion'
INSERT INTO transaccion (transaccion_id, cuenta_id, tipo_transaccion, monto) VALUES
(101, 1, 'DEPÓSITO', 500.00),
(102, 1, 'RETIRO', 100.00),
(103, 2, 'DEPÓSITO', 1200.00),
(104, 3, 'RETIRO', 50.00);

-- 5. Consulta para verificar la relación
SELECT 
    t.transaccion_id,
    c.titular,
    c.tipo_cuenta,
    t.tipo_transaccion,
    t.monto,
    t.fecha_transaccion
FROM transaccion t
INNER JOIN cuenta c ON t.cuenta_id = c.cuenta_id
ORDER BY t.transaccion_id ASC;