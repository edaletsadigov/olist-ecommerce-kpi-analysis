# Notebook — `E_Commerce_Operations.ipynb`

Python layer on top of the SQL in [`../queries/queries.sql`](../queries/queries.sql). The notebook connects to Oracle, creates the analytical views, runs Q1–Q10, and turns the results into four charts and a correlation check.

## Flow

| Section | Content |
|---|---|
| Libraries | `oracledb`, SQLAlchemy, pandas, numpy, matplotlib, seaborn |
| Connection | SQLAlchemy engine to Oracle (`oracle+oracledb`), password entered with `getpass` |
| Q1–Q10 | Each query is stored as a string and loaded with `pd.read_sql` |
| Charts | Four figures, exported to [`../charts/`](../charts/) |
| Operational insights | Five findings with recommended actions |

The SQL here is identical to `queries.sql`, so a change in one place should be mirrored in the other.

## Setup

```bash
pip install -r requirements.txt
```

1. Load the nine Olist CSV files into an Oracle schema (see [`../data/README.md`](../data/README.md)).
2. In the connection cell, set `username`, `host`, `port` and `service_name` for your instance. The password is requested at runtime and is never stored in the notebook.
3. Run all cells top to bottom. Q2 creates the three views the later queries depend on.

## Statistics in the notebook

- **Pearson r** and **Spearman rho** between average delivery days and average review score, calculated across categories with at least 100 orders.
- The trend line in the scatter chart is a first-degree `numpy.polyfit`.
- The notebook states that this is a category-level correlation. It is not evidence that slow delivery causes low ratings.

## Before publishing

- Use **Restart kernel and run all** so every cell holds its output. In the uploaded copy, the Q4 cell raised a `DatabaseError` and the cells after it were not executed, so the notebook contains no tables or charts yet.
- The "Operational insights" cell contains unfilled placeholders (`[___]`) and some numbers that do not match the query results. Replace them with the verified figures in the main [README](../README.md).

