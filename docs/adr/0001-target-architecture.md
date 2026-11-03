# ADR-0001: Adopt a Lakehouse architecture with medallion layers

- **Status:** proposed
- **Date:** 2026-10-18
- **Author:** Luli MARUYAMA
- **Lesson:** L01

## Context

Albert's Marketplace currently operates a single PostgreSQL database containing 25 tables. The web shop writes to it in real-time (checkout, reviews, passwords, saved cards), while analysts query the exact same tables directly for reporting. A nightly CSV export is also manually opened in spreadsheets by the business.

   This setup is none of the four architectures: it is an operational database used for analytics, with no integration of several sources and no history. It creates three critical problems:
1. **Workload collision:** The web shop and analysts compete for the same database resources, meaning checkout performance is tied to reporting load.
2. **Inconsistent reporting:** Analysts query live, mutable tables at different times without a consistent snapshot, which is why "the reports disagree on revenue, and nobody can say which one is right."
3. **Security and Governance risk:** The database holds sensitive data (saved cards, passwords) and analysts can technically access it, violating European data protection law (GDPR). Furthermore, the data is up to 24 hours stale due to the nightly CSV bottleneck.

The business now requires reliable daily data to feed an ML model: units sold per product, per country, per day. We need a scalable, governed architecture that separates the operational database from analytics, serving both SQL-based analysts and Python-based ML engineers.

## Options considered

| Option | For | Against |
|---|---|---|
| **Warehouse** | Excellent for BI and SQL-based reporting; high performance for structured data; robust access control and governance. | Poor support for unstructured data (review text); expensive for raw storage; ML teams struggle to access and process data for feature engineering. |
| **Lake** | Cheap, virtually unlimited storage; excellent for ML and raw data; flexible schema supports text and images. | Lacks native ACID transactions and SQL performance out-of-the-box; governance and access control require significant manual configuration; risk of becoming a "data swamp". |
| **Lake + warehouse (Two-tier)** | Separates workloads: warehouse for BI, lake for ML; each engine does what it does best. | Data duplication; complex to keep both systems in sync; double the infrastructure and governance overhead. |
| **Lakehouse** | Unified platform; supports both BI/SQL and ML; cheap object storage with ACID transactions and native governance; single source of truth. | Newer paradigm; requires data engineering discipline to manage file layouts (avoiding the "small files" problem); requires upskilling. |

## Criteria

We evaluated each option against the decision frame. Scoring: ✅ = fits, ❌ = does not fit, ⚠️ = depends.

| Criteria | Warehouse | Lake | Lake + Warehouse | Lakehouse |
|---|---|---|---|---|
| **Workload** (BI & ML) | ⚠️ BI only | ⚠️ ML only | ✅ Both | ✅ Both |
| **Data types** (tables, text) | ✅ Structured only | ✅ All types | ✅ All types | ✅ All types |
| **Freshness** (daily) | ✅ | ✅ | ✅ | ✅ |
| **Team and skills** (SQL, Python) | ✅ SQL | ❌ Ops-heavy | ⚠️ Mixed | ✅ SQL + Python |
| **Cost** (storage, compute) | ❌ High for storage | ✅ Cheap | ❌ Double cost | ✅ Cheap storage, pay-per-query compute |
| **Governance** (GDPR, access) | ✅ Strong | ⚠️ Weak by default | ⚠️ Split | ✅ Unified |

**Justification for the scores:**
- **Workload:** The Lakehouse is the only option that natively supports both SQL (analysts) and Python (ML) without duplicating the data.
- **Data types:** The marketplace has structured orders but also free-text reviews. The Lakehouse handles both natively via object storage.
- **Team:** The group consists of data engineers using SQL and Python. We do not have the capacity to self-manage a traditional Hadoop data lake, so a managed Lakehouse is required.
- **Cost:** Storing raw data in a warehouse is expensive. A Lakehouse uses cheap cloud object storage and only provisions compute when queries run.
- **Governance:** We must protect PII (passwords, saved cards) at the storage layer. The Lakehouse allows unified access controls and metadata management across all data.

## Decision

We will adopt a **Lakehouse architecture** using a **Medallion layer structure** (Bronze, Silver, Gold).

## Consequences

**What becomes easier:**
- **Single source of truth:** Analysts and the ML team will query the same Gold tables, meaning revenue figures and daily demand units will finally reconcile.
- **Separation of concerns:** The operational PostgreSQL database is freed from analytical workloads, securing checkout performance.
- **Governance:** PII will be masked in the Silver layer, meaning analysts and ML can work safely without seeing sensitive customer data, ensuring GDPR compliance.
- **Scalability:** The platform can scale to store historical raw data (Bronze) indefinitely at a low cost.

**What becomes harder:**
- **Pipeline maintenance:** Unlike a simple CSV export, we now have to maintain ingestion pipelines and transformations (dbt).
- **File management:** Working with object storage (Parquet) requires discipline around file sizes and partitioning to avoid performance degradation.

**What we will have to watch:**
- **Bronze immutability:** We must enforce a strict rule that Bronze holds *exactly* what arrived. If we clean data in Bronze, we lose our audit trail and the ability to debug issues.
- **Cost of compute:** While storage is cheap, poorly written queries in the Lakehouse can scan terabytes of data and result in high bills. We will need to monitor bytes processed.
- **Small files problem:** Streaming data and frequent batch loads can create thousands of tiny files, which slows down queries. We will need compaction strategies.
