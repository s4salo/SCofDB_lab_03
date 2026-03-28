# Отчёт по лабораторной работе №3
## Диагностика и оптимизация маркетплейса

**Студент:** Гаврилюк А.В.  
**Группа:** БПМ-22-ПО-3
**Дата:** 27.03.2026

---

## 1. Исходные данные

### 1.1 Использованная схема
Использована схема из файла:
`backend/migrations/001_init.sql`

---

### 1.2 Объём данных

После генерации данных:

- users: 10 000  
- orders: 100 000  
- order_items: 400 000  
- order_status_history: 199 904  

---

## 2. Найденные медленные запросы (до оптимизации)

### Запрос №1

**SQL:**
```sql
SELECT *
FROM orders
WHERE status = 'paid'
ORDER BY created_at DESC
LIMIT 20;
```

**План (ключевое):**
- Seq Scan on orders
- Sort (top-N heapsort)

**Execution Time:** ~30 ms  

**Почему медленный:**
Полное сканирование таблицы (~100k строк) и сортировка большого числа записей.

---

### Запрос №2

**SQL:**
```sql
SELECT *
FROM orders
WHERE status = 'paid'
  AND created_at >= '2025-01-01'
  AND created_at < '2025-04-01';
```

**План:**
- Seq Scan on orders

**Execution Time:** ~17 ms  

**Почему медленный:**
Отсутствует индекс по полям фильтрации, используется полный перебор.

---

### Запрос №3

**SQL:**
```sql
SELECT o.user_id, SUM(oi.price * oi.quantity) AS total
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
WHERE o.status IN ('paid', 'completed')
GROUP BY o.user_id
ORDER BY total DESC
LIMIT 10;
```

**План:**
- Hash Join
- GroupAggregate
- Sort (external merge, диск)

**Execution Time:** ~1728 ms  

**Почему медленный:**
Обработка сотен тысяч строк, тяжёлая агрегация и сортировка с использованием диска.

---

### Запрос №4

**SQL (смысл):**
Поиск заказов со статусом `paid`, которые долго не переходят в `shipped`.

**План:**
- Hash Anti Join
- вложенные подзапросы
- Seq Scan

**Execution Time:** ~817936 ms (~13.6 минут)

**Почему медленный:**
Множественные полные сканирования и отсутствие индексов в подзапросах.

---

## 3. Добавленные индексы и обоснование типа

### Индекс №1
- SQL:
```sql
CREATE INDEX idx_orders_status_created_at
ON orders (status, created_at DESC);
```
- Какой запрос ускоряет: Q1, Q2  
- Почему выбран тип:
BTREE — оптимален для равенства (`status`) и сортировки (`created_at`).

---

### Индекс №2
- SQL:
```sql
CREATE INDEX idx_order_items_order_id
ON order_items (order_id);
```
- Какой запрос ускоряет: Q3  
- Почему выбран тип:
BTREE — эффективен для JOIN по ключу.

---

### Индекс №3
- SQL:
```sql
CREATE INDEX idx_order_status_history_order_id_status
ON order_status_history (order_id, status);
```
- Какой запрос ускоряет: Q4  
- Почему выбран тип:
BTREE — позволяет выполнять быстрый поиск и Index Only Scan.

---

## 4. Замеры до/после индексов

- Query 1: 30 ms → 0.195 ms → ускорение
- Query 2: 17 ms → 11.805 ms → ускорение
- Query 3: 728 ms → 714 ms → нет ускорения
- Query 4: 817936 ms → 449 ms → ускорение 

---

## 5. Партиционирование `orders` по дате

### 5.1 Выбранная стратегия
RANGE-партиционирование по `created_at` (по кварталам).

---

## 6. Итоговые замеры (после партиционирования)

- Query 1: 30 ms → 0.195  ms → 0.124 ms  
- Query 2: 20 ms → 11.805 ms → 12.386 ms  
- Query 3: 728 ms → 714 ms → 720.039 ms  
- Query 4: 817936 ms → 449 ms → 289 ms  

---

## 7. Что удалось исправить

- устранён Seq Scan в критичных запросах
- ускорена сортировка через индекс
- подзапросы оптимизированы (Index Only Scan)
- Q4 ускорен с ~13 минут до <1 секунды
- внедрён partition pruning

---

## 8. Выводы

1. Индексы критически важны для WHERE и ORDER BY.
2. Наибольший эффект — в сложных запросах с подзапросами.
3. Партиционирование эффективно при фильтрации по диапазону.
4. GROUP BY требует дополнительных подходов (агрегации).
5. EXPLAIN ANALYZE — основной инструмент оптимизации.
