# Olist KPI Framework — SQL (Oracle) + Python

An end-to-end KPI analysis of the Olist Brazilian e-commerce marketplace. The project builds a revenue-safe analytical base in Oracle SQL, reconciles it against the raw tables, computes category, monthly and seller KPIs, and visualizes the results in Python.

**Author:** Ədalət Sadıqov
**Stack:** Oracle SQL (views, CTEs, window functions) · Python (pandas, SQLAlchemy, matplotlib, seaborn)

---

## Headline numbers

Delivered orders only, 2016–2018. Prices in BRL, freight excluded.

| KPI | Value |
|---|---:|
| Total revenue | **13,221,498** |
| Delivered orders | 96,478 (97.0% of all orders) |
| Average order value (AOV) | 137.04 |
| Average delivery time | 12.5 days |
| Average review score | 4.16 / 5 |
| Product categories | 74 |
| Active sellers | 2,970 |

---

## Repository structure

```
├── README.md                  ← you are here
├── sql/
│   ├── queries.sql            Q1–Q10 in Oracle SQL
│   └── README.md              query guide, design decisions
├── notebook/
│   ├── E_Commerce_Operations.ipynb
│   └── README.md              setup and notebook flow
├── charts/
│   ├── *.png                  four exported charts
│   └── README.md              what each chart shows
├── data/
│   └── README.md              datasets, relationships, data-quality notes
└── requirements.txt
```

---

## The methodological finding: join fan-out

The mandatory reconciliation step (Q3) compares revenue computed directly from `olist_order_items` with revenue computed from a fully joined table.

| Step | Rows | Revenue (BRL) |
|---|---:|---:|
| Items only | 110,197 | 13,221,498.11 |
| + products | 110,197 | 13,221,498.11 |
| + category translation | 110,197 | 13,221,498.11 |
| + raw reviews | 139,037 | 16,691,714.62 |

Only the reviews join changes the numbers. One order can carry several reviews, so each item row is repeated and `SUM(price)` is overstated by **26.25%** in this Oracle load. Keeping one review per order (`ROW_NUMBER()`) fixes it, and the corrected base matches the direct sum exactly.

**Why it matters:** a dashboard built on the naive join would report 3.47M BRL of revenue that does not exist, with no error message. Reconciling every base table against its source before computing KPIs is the habit this project is built around.

**Data-quality caveat:** the official reviews file has 99,224 rows, while the Oracle table has 121,648. On the official files the same fan-out inflates revenue by only 0.44%. The 26.25% figure is therefore specific to this load, probably caused by multi-line comments split during import (unconfirmed). The mechanism and the fix are the same either way.

---

## Insights

Figures below were checked against the query logic on the official Olist files. Every correlation below is observational.

### 1. Revenue is spread across categories, not concentrated in one
`health_beauty` is the largest category with 1.23M BRL, **9.3%** of revenue. The top 5 together hold **39.8%** and the top 10 hold **62.4%** across 74 categories. A loss in one category is survivable. A loss across the top five would not be.
**Action:** monitor the top five categories with revenue alerts, and grow mid-tier categories that already show good ratings.

### 2. Slow delivery goes with low satisfaction
- At **order level** (95,824 orders), average review falls from **4.41** (delivered in 0–7 days) to **4.30** (8–14), **4.12** (15–21) and **3.06** (22+ days). Correlation r = −0.33.
- Orders delivered **after the estimated date** (8.1% of delivered orders) average **2.57**, against **4.29** for on-time orders.
- At **category level**, r = −0.58 across 52 categories, driven partly by `office_furniture`; without it r = −0.42.

**Correlation is not causation.** Late orders may also involve damaged goods or wrong items, and category, price and seller location can influence both delivery and rating.
**Action:** set a maximum delivery-time SLA per category, flag sellers who miss the estimated date, and send proactive delay notices.

### 3. `office_furniture` is the one weak, high-volume category
Score 3.65 over 1,254 orders, against 4.16 overall, and the slowest category at 20.6 days. The other weak categories (`audio`, `fashion_male_clothing`, `home_confort`, `fixed_telephony`) score 3.82–3.97 and have lower volume.
**Action:** split complaints into logistics and product quality before assigning an owner. Bulky-item delivery is a plausible driver, but this analysis cannot confirm it.

### 4. Seller base is fragmented
The top 10 of 2,970 sellers generate **13.3%** of revenue and the single largest seller 1.7%. No single seller is critical, but the top group still carries a meaningful share.
**Action:** protect top sellers with retention programs and check that their delivery time and ratings are not below the platform averages (12.5 days, 4.16).

### 5. Growth is step-shaped, and peaks hurt service quality
Revenue grows through 2017, reaches **987,765 BRL in November 2017 (+52% vs October)** and then plateaus around 0.83–0.98M BRL a month in 2018. In the stressed months, service worsens: November 2017 delivery time rises from 11.7 to **15.1 days** while the review score falls from 4.20 to 3.99. February–March 2018 are the weakest months for ratings (3.88 and 3.81, with 16.9 and 16.2 delivery days). By August 2018, delivery time is down to 7.7 days.
**Action:** plan logistics capacity and seller stock ahead of peak months. The link between volume and delays is a pattern in time, not proven causation.

---

## Data limitations

- **Reviews table size.** Oracle holds 121,648 review rows against 99,224 in the official file, so review-based averages in an Oracle run may differ slightly from the figures above.
- **Delivered orders only.** Canceled and in-transit orders are excluded, so these KPIs describe fulfilled demand.
- **Revenue excludes freight** (2.20M BRL on delivered orders).
- **Thin edges.** Sep–Dec 2016 contains 267 delivered orders in total. Monthly trends are reliable from January 2017.
- **Unknown category.** 1,392 orders (1.3% of revenue) have no product category.
- **Category averages hide order-level variation.** The category scatter has only 52 points and one strong outlier.

---

## How to run

1. Load the nine Olist CSV files into Oracle (see [`data/README.md`](data/README.md)).
2. `pip install -r requirements.txt`
3. Open `notebook/E_Commerce_Operations.ipynb`, set the connection details, and run all cells.
4. Or run `sql/queries.sql` directly in SQL Developer.

## Skills demonstrated

Multi-table joins and grain control · revenue reconciliation · CTEs and views · window functions (`ROW_NUMBER`, `RANK`) · Python–Oracle integration · correlation analysis with explicit causal caveats · data-quality diagnosis
