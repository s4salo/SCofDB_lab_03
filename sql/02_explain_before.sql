\timing on
\echo '=== BEFORE OPTIMIZATION ==='

-- Рекомендуемые настройки для сравнимых замеров
SET max_parallel_workers_per_gather = 0;
SET work_mem = '32MB';
ANALYZE;

-- ============================================
-- Q1: Фильтрация по статусу + сортировка по дате
-- Типичный запрос: показать последние оплаченные заказы
-- ============================================
\echo '--- Q1: Фильтрация по статусу + сортировка по дате ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.id, o.user_id, o.status, o.total_amount, o.created_at
FROM orders o
WHERE o.status = 'paid'
ORDER BY o.created_at DESC
LIMIT 20;

-- ============================================
-- Q2: Фильтрация по статусу + диапазону дат
-- Типичный запрос: найти все paid-заказы за 2025 год
-- ============================================
\echo '--- Q2: Фильтрация по статусу + диапазону дат ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.id, o.user_id, o.total_amount, o.created_at
FROM orders o
WHERE o.status = 'paid'
  AND o.created_at >= '2025-01-01'
  AND o.created_at <  '2025-04-01';

-- ============================================
-- Q3: JOIN orders + order_items + GROUP BY
-- Типичный запрос: топ пользователей по сумме заказов
-- ============================================
\echo '--- Q3: JOIN + GROUP BY (топ пользователей по выручке) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.user_id,
       count(DISTINCT o.id)  AS order_count,
       sum(oi.price * oi.quantity) AS total_spent
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
WHERE o.status IN ('paid', 'completed')
GROUP BY o.user_id
ORDER BY total_spent DESC
LIMIT 10;

-- ============================================
-- (Опционально) Q4: полный агрегат по периоду, который сложно ускорить индексами
-- ============================================
\echo '--- Q4: Заказы в статусе "paid" которые долго не становятся "shipped" ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.id, o.user_id, o.total_amount, o.created_at,
       (SELECT changed_at FROM order_status_history osh
        WHERE osh.order_id = o.id AND osh.status = 'paid'
        ORDER BY changed_at DESC LIMIT 1) as paid_at
FROM orders o
WHERE o.status = 'paid'
  AND EXISTS (
    SELECT 1 FROM order_status_history osh
    WHERE osh.order_id = o.id AND osh.status = 'paid'
  )
  AND NOT EXISTS (
    SELECT 1 FROM order_status_history osh
    WHERE osh.order_id = o.id AND osh.status = 'shipped'
  )
  AND o.created_at < NOW() - INTERVAL '1 day'
ORDER BY o.created_at;