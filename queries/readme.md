# SQL — `queries.sql`

Ten Oracle SQL queries (Q1–Q10) that build a trustworthy analytical base for the Olist marketplace and compute the KPIs on top of it.

- **Dialect:** Oracle Database (XE, pluggable DB `XEPDB1`)
- **Schema:** nine Olist tables (see [`../data/README.md`](../data/README.md))
- **Run order:** top to bottom. Q2 creates three views that Q3–Q10 depend on.

## The core idea: three grains, three views

Olist data lives at different grains. Mixing them in one SUM or AVG is how revenue gets double-counted. Q2 therefore creates one base view and two derived views, and each KPI reads from the grain it belongs to.

| View | Grain (one row per…) | Used for |
|---|---|---|
| `v_analytical_base` | order item (delivered orders only) | revenue, seller and category joins |
| `v_order_base` | order | AOV, delivery days, review score |
| `v_order_category` | order × category | category-level KPIs |

## Query guide

| # | What it answers | Key technique |
|---|---|---|
| Q1 | Row counts per table; average items per order (1.142 avg, median 1, max 21) | `UNION ALL`, CTE, `MEDIAN` |
| Q2 | Analytical base views for delivered orders | `ROW_NUMBER()` to keep one review per order, `COALESCE` for category fallback |
| Q3 | **Revenue reconciliation**: direct sum vs naive join vs fixed base | Row/revenue check after each added join |
| Q4 | Total revenue, AOV, average delivery days, average review score | Order-grain view |
| Q5 | The same KPIs per English category name, sorted by revenue | `COUNT(DISTINCT)` on order-category grain |
| Q6 | Monthly KPIs | `TO_CHAR(..., 'YYYY-MM')` |
| Q7 | Top 5 and bottom 5 categories by revenue | Two `ROW_NUMBER()` rankings in one CTE |
| Q8 | Top 5 and bottom 5 categories by review score, min. 100 orders | `HAVING` to remove tiny categories |
| Q9 | Seller KPIs with revenue rank | `RANK() OVER` on a seller × order pre-aggregation |
| Q10 | Delivery days vs review score per category (min. 100 orders) | Feeds the correlation in the notebook |

## Q3 — the reconciliation

The check compares three revenue figures:

1. **Direct:** `SUM(price)` over `olist_order_items` joined to delivered orders.
2. **Naive base:** the same sum after adding products, translation, sellers and the raw reviews table.
3. **Fixed base:** `SUM(price)` over `v_analytical_base`.

The step-by-step query shows that products, translation and sellers add **zero** rows (many-to-one joins). Only `olist_order_reviews` multiplies rows, because one order can have several reviews (one-to-many). The fix is the `latest_review` CTE in Q2, which keeps one review per order. After that, fixed revenue equals direct revenue and the check returns `PASS`.

**Result in the author's Oracle load:** 110,197 rows became 139,037 (+28,840) and revenue went from 13,221,498.11 to 16,691,714.62 BRL (**+26.25%**).

> **Data-quality note.** The official Olist reviews file has 99,224 rows. The Oracle table used here has 121,648. Re-running the same joins on the official files gives only +643 rows (+0.44%). The mechanism is identical, but the size of the inflation depends on the load. A likely cause is multi-line review comments being split into extra rows during import. This is unconfirmed and worth checking.

## Design decisions

- **Delivered orders only.** `order_status = 'delivered'` keeps 96,478 of 99,441 orders (97.0%). Canceled, unavailable and in-transit orders are excluded from every KPI.
- **Revenue = item `price`.** Freight is not included.
- **Delivery days** = purchase date to customer delivery date, both truncated to dates.
- **`MIN(delivery_days)` / `MIN(review_score)` in the order views** are safe because those values are identical for every item of the same order. `MIN` is only there to collapse the grain.
- **`HAVING COUNT(DISTINCT order_id) >= 100`** in Q8 and Q10 stops a category with a handful of orders from topping or bottoming a ranking.

## Known caveat and suggested fix

The `latest_review` CTE orders by `review_answer_timestamp DESC`. In Oracle, `DESC` places `NULL` first by default. If the reviews table contains rows with a null timestamp (see the data-quality note), those rows would win the ranking. Making the order explicit removes the risk:

```sql
ORDER BY review_answer_timestamp DESC NULLS LAST, review_id
```

