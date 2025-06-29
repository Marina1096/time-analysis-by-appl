# Credit Application Processing Analytics

> **Проект:** моделирование и аналитика процесса обработки кредитных заявок (Потребительский / Автокредит / Кредитные карты) банка‑заказчика.
> **Период данных:** Март 2025 г. (рабочие часы 09‑18 МСК, праздники — 8 марта).
> **Цель:** выявить «узкие места» и сократить цикл решения до ≤ 24 ч.

---

## Репозиторий

```
├─ 01_schema_and_dicts.sql      -- DDL + справочники (branch / manager / stage / result)
├─ 02_clients.csv               -- 1 000 обезличенных клиентов  (UTF‑8 ;‑sep)
├─ 03_generator_current.sql     -- → функции + процедуры генерации марта‑2025
│   ├─ add_work_hours()         -- расчёт конца этапа в раб. время
│   ├─ generate_march25_data()  -- генератор заявок + логов + скоринга
│   └─ close_at_month_end()     -- обрезает всё, что вышло в апрель
├─ BRD.docx                     -- Business Requirements Document
├─ FSD Кредитные заявки.doc     -- Functional Specification (генератор + отчёты)
├─ Скрипты отчетов в Metabase.txt-- 5 native‑SQL запросов (Pie / Bar / Line / KPI)
└─ README.md                    -- вы здесь
```

### Основные сущности

| Слой                  | Таблицы / объекты                                                               | Назначение                        |
| --------------------- | ------------------------------------------------------------------------------- | --------------------------------- |
| **Справочники**       | `branch_dict`, `manager_dict`, `stage_dict`, `stage_result_dict`, `client_dict` | статика для генератора и отчётов  |
| **Факт**              | `loan_applications` (заявка‑шапка)                                              | ключ `application_id`             |
|                       | `application_processing_log`                                                    | тайм‑линия этапов + комментарии   |
|                       | `scoring_results`                                                               | скоринговый балл > 80/ < 30       |
| **Служебные функции** | `add_work_hours(ts,h,holidays[])`                                               | гарантирует конец ≤ 17:59:59 М‑Пт |
| **Процедуры**         | `generate_march25_data()`                                                       | генерация мартовского потока      |
|                       | `close_at_month_end()`                                                          | отсекает «апрельские» хвосты      |

---

## Quick Start (локально)

1. Поднять PostgreSQL ≥ 11 (Docker‑образ `postgres:16`).
2. Выполнить скрипты **в указанном порядке**:

   ```bash
   psql -U postgres -f 01_schema_and_dicts.sql
   \copy credit.client_dict FROM '02_clients.csv' CSV HEADER DELIMITER ';'
   psql -U postgres -f 03_generator_current.sql
   ```
3. Запустить Metabase (Docker):

   ```bash
   docker run -d -p 3000:3000 --name metabase -e MB_DB_FILE=/metabase.db \
              -v $PWD/metabase.db:/metabase.db metabase/metabase
   ```
4. Подключить БД *credit* ➜ импортировать запросы из **Скрипты отчетов в Metabase.txt**.
5. Создать дашборд, привязать общие фильтры:

   * `credit_type` · `branch_city` · `region_name` · `channel` · `application_date` · `snapshot_date`.

---

## Метрики дашборда

| Виджет                         | Описание                                                     | Файл‑запрос   |
| ------------------------------ | ------------------------------------------------------------ | ------------- |
| Pie «Причины отказа»           | Отказы этапов 2 & 4, нормализация авто‑отклонения < 30 score | `Скрипты…` №1 |
| KPI «% нарушений SLA»          | Цикл > 24 ч                                                  | `Скрипты…` №2 |
| Bar «Среднее время этапов»     | AVG(end‑start) по каждому stage                              | №3            |
| Histogram + KPI «Full cycle»   | Распределение total\_hours                                   | №4            |
| Таблицы «Задержки Stage 2 / 4» | Список заявок > AVG(stage)                                   | №5            |

---

## Архитектура и масштабирование

* **Готовность к горизонтальному партиционированию по филиалу** (`branch_id`) — все PK/FK учитывают ключ; при росте объёма включает partitioning без refactor.
* Периодический ETL не нужен: синтетика генерируется stored‑процедурой; для PROD заменится на реальный поток.

---

## Использованные технологии

* **PostgreSQL 16** — основная БД, PL/pgSQL‑скрипты.
* **Metabase v0.49** (Docker) — BI‑слой.
* **Markdown / Docx** — BRD, FSD.

---

## Лицензия

Проект распространяется под MIT License — см. файл `LICENSE` (добавьте при необходимости).
