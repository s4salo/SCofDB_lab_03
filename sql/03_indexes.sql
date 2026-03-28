\timing on
\echo '=== APPLY INDEXES ==='

-- ============================================
-- Индекс 1:
-- ============================================
-- Ускоряет: Q1 и Q2 — фильтрация по status + сортировка/диапазон по created_at.
-- Почему BTREE: данные непрерывны по дате и фильтруются по равенству + диапазону
CREATE INDEX IF NOT EXISTS idx_orders_status_created_at
    ON orders USING BTREE (status, created_at DESC);

-- ============================================
-- Индекс 2:
-- ============================================
-- Ускоряет: Q3 — JOIN orders ⟶ order_items по order_id.
-- Почему BTREE: точный lookup по UUID-ключу; BTREE оптимален для равенства и IN.
CREATE INDEX IF NOT EXISTS idx_order_items_order_id
    ON order_items USING BTREE (order_id);

-- =============================================
-- Индекс 3
-- =============================================
CREATE INDEX IF NOT EXISTS idx_order_status_history_order_id_status ON order_status_history
USING BTREE (order_id, status, changed_at DESC);
-- - Ускорит Q4 (последовательное сканирование для каждого заказа)
-- - Покрывающий индекс: содержит все нужные поля (order_id, status, changed_at)
-- - ORDER BY changed_at DESC уже учтено в индексе

ANALYZE order_items;
ANALYZE order_status_history;

\echo '=== Indexes created successfully ==='