\timing on
\echo '=== PARTITION ORDERS BY DATE ==='

-- ============================================
-- Стратегия: RANGE-партиционирование по created_at, по кварталам.
-- Диапазон данных в seed: 2024-01-01 … 2026-01-01 → 8 кварталов.
-- Квартальный шаг выбран как компромисс:
--   - месячный слишком мелко (24 партиции, накладные расходы планировщика),
--   - годовой слишком крупно (нет pruning внутри года).
-- ============================================

-- ============================================
-- Шаг 1: Создаём новую партиционированную таблицу
-- ============================================
CREATE TABLE IF NOT EXISTS orders_partitioned (
    id            UUID          NOT NULL DEFAULT uuid_generate_v4(),
    user_id       UUID          NOT NULL,
    status        TEXT          NOT NULL DEFAULT 'created',
    total_amount  DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    PRIMARY KEY (id, created_at)          -- partition key обязан входить в PK
) PARTITION BY RANGE (created_at);

-- ============================================
-- Шаг 2: Создаём партиции по кварталам
-- ============================================

-- 2024
CREATE TABLE IF NOT EXISTS orders_2024_q1
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');

CREATE TABLE IF NOT EXISTS orders_2024_q2
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-04-01') TO ('2024-07-01');

CREATE TABLE IF NOT EXISTS orders_2024_q3
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-07-01') TO ('2024-10-01');

CREATE TABLE IF NOT EXISTS orders_2024_q4
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-10-01') TO ('2025-01-01');

-- 2025
CREATE TABLE IF NOT EXISTS orders_2025_q1
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2025-04-01');

CREATE TABLE IF NOT EXISTS orders_2025_q2
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-04-01') TO ('2025-07-01');

CREATE TABLE IF NOT EXISTS orders_2025_q3
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-07-01') TO ('2025-10-01');

CREATE TABLE IF NOT EXISTS orders_2025_q4
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-10-01') TO ('2026-01-01');

-- DEFAULT-партиция для данных вне диапазона (будущие даты и т.п.)
CREATE TABLE IF NOT EXISTS orders_default
    PARTITION OF orders_partitioned DEFAULT;

-- ============================================
-- Шаг 3: Перенос данных из исходной таблицы
-- ============================================
\echo '--- Перенос данных в партиционированную таблицу ---'

INSERT INTO orders_partitioned (id, user_id, status, total_amount, created_at)
SELECT id, user_id, status, total_amount, created_at
FROM orders;

-- Проверка количества строк
\echo '--- Проверка: количество строк до/после ---'
SELECT 'orders (исходная)'       AS source, count(*) FROM orders
UNION ALL
SELECT 'orders_partitioned',              count(*) FROM orders_partitioned
UNION ALL
SELECT 'orders_2024_q1',                  count(*) FROM orders_2024_q1
UNION ALL
SELECT 'orders_2024_q2',                  count(*) FROM orders_2024_q2
UNION ALL
SELECT 'orders_2024_q3',                  count(*) FROM orders_2024_q3
UNION ALL
SELECT 'orders_2024_q4',                  count(*) FROM orders_2024_q4
UNION ALL
SELECT 'orders_2025_q1',                  count(*) FROM orders_2025_q1
UNION ALL
SELECT 'orders_2025_q2',                  count(*) FROM orders_2025_q2
UNION ALL
SELECT 'orders_2025_q3',                  count(*) FROM orders_2025_q3
UNION ALL
SELECT 'orders_2025_q4',                  count(*) FROM orders_2025_q4
UNION ALL
SELECT 'orders_default',                  count(*) FROM orders_default;

-- ============================================
-- Шаг 4: Индексы на партиционированной таблице
-- ============================================

-- Составной индекс status + created_at
CREATE INDEX IF NOT EXISTS idx_op_status_created_at
    ON orders_partitioned USING BTREE (status, created_at DESC);

-- BRIN на created_at внутри каждой партиции
CREATE INDEX IF NOT EXISTS idx_op_created_at_brin
    ON orders_partitioned USING BRIN (created_at);

-- ============================================
-- Шаг 5: ANALYZE + проверка partition pruning
-- ============================================
ANALYZE orders_partitioned;

\echo '--- Проверка partition pruning: запрос за Q1 2025 ---'
-- Планировщик должен трогать ТОЛЬКО партицию orders_2025_q1
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM orders_partitioned
WHERE created_at >= '2025-01-01'
  AND created_at <  '2025-04-01';

\echo '=== Partitioning complete ==='