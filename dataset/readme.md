# Data — Olist Brazilian E-Commerce

**Source:** *Brazilian E-Commerce Public Dataset by Olist*, published by Olist on Kaggle. Check the Kaggle page for current license terms.

## Download

| | |
|---|---|
| **Kaggle page** | [kaggle.com/datasets/olistbr/brazilian-ecommerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) |
| **Files** | 9 CSV files (`olist_geolocation_dataset.csv`, 1M rows, is the largest) |
| **Access** | A free Kaggle account is required to download |

**Option 1: browser.** Open the Kaggle page, click **Download**, and unzip the archive.

**Option 2: Kaggle CLI.**

```bash
pip install kaggle
kaggle datasets download -d olistbr/brazilian-ecommerce --unzip -p data/raw
```

The CLI needs an API token (`kaggle.json`) from your Kaggle account settings.

The CSV files are listed in `.gitignore` and are not stored in this repository.

**Coverage:** about 100,000 orders placed between **4 Sep 2016 and 17 Oct 2018** on Brazilian marketplaces, with items, payments, reviews, products and sellers. Prices are in Brazilian reais (BRL).

After downloading, load the CSV files into Oracle as tables with the names below.

## Tables

| Table | Row count in the Oracle load | Official file row count | Role in this project |
|---|---:|---:|---|
| `olist_orders` | 99,441 | 99,441 | Order status and timestamps, the base of every KPI |
| `olist_order_items` | 112,650 | 112,650 | Price and freight per item, the revenue source |
| `olist_products` | 32,951 | 32,951 | Product category |
| `name_translation` | 71 | 71 | Portuguese to English category names (`name`, `name_english`) |
| `olist_sellers` | 3,095 | 3,095 | Seller city and state |
| `olist_order_reviews` | **121,648** | **99,224** | Review score |
| `olist_customers` | 99,441 | 99,441 | Loaded, not used in the KPIs |
| `olist_order_payments` | 103,886 | 103,886 | Loaded, not used in the KPIs |
| `olist_geolocation` | 1,000,163 | 1,000,163 | Loaded, not used in the KPIs |

Row counts in the Oracle column come from query Q1. Official counts are the published file sizes.

## Relationships

```
olist_orders 1 ──< olist_order_items >── 1 olist_products >── 1 name_translation
     │                    │
     │                    └──────────── >── 1 olist_sellers
     └──< olist_order_reviews          (one order can have several reviews)
```

`olist_order_reviews` is the only one-to-many join from an order. It is the source of the revenue double-counting studied in Q3.

## Things to know before using the data

- **Reviews table size.** The Oracle table has 22,424 more rows than the official file. Likely cause: review comments containing line breaks were split into several rows during import. This is unconfirmed. Verify row count and `review_score` values (they should be integers 1–5) after loading.
- **Delivered orders only.** 96,478 of 99,441 orders (97.0%) are `delivered`. The rest are shipped (1,107), canceled (625), unavailable (609), invoiced (314), processing (301), created (5) or approved (2).
- **Sparse edges.** September 2016 and December 2016 have one delivered order each, and there is no delivered order in November 2016. Meaningful monthly data starts in January 2017.
- **Category gaps.** Some products have no category. They appear as `unknown` (1,392 orders, about 170,700 BRL, 1.3% of revenue). Untranslated names fall back to the Portuguese name.
- **Category name spellings.** The source uses `home_confort` and `home_comfort_2` as separate categories.
- **Product column names** keep the original misspelling (`product_name_lenght`).
