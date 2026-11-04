# Architecture

> Update this page at the end of every lesson. It is the diagram you present at
> the oral defence.

## Context

Albert's Marketplace is a European marketplace for beauty products. Today, one PostgreSQL database serves both the web shop and the analysts, so reports slow down checkout and two reports give two different revenue figures. The platform must serve two users: analysts, who need one agreed revenue figure, and the ML team, who need units sold per product, per country, per day. Daily freshness is enough for both; nothing needs real-time data. Two constraints matter: the shop's database must not carry analytical load, and passwords and card numbers must never leave it.

## Architecture (after L02)

Solid lines exist today. Dotted lines are planned.

```mermaid
flowchart LR
  shop["Web shop<br/>checkout, reviews"] -->|writes| pg[("PostgreSQL<br/>shop database")]
  pg -->|"legacy CSV export<br/>(release v1.0.0)"| load["load_bronze_export.py<br/>run by hand, 2026-11-03"]
  load -->|"7 tables<br/>no passwords or cards"| bronze
  subgraph gcs["gs://data-engineering-i2-group2 · europe-west1 · not public"]
    bronze[("Bronze · Parquet, Snappy<br/>orders, order_items: one folder per day<br/>5 reference tables: one folder each<br/>2,197 files, 89 MiB")]
    readers["Access: all members of<br/>project data-engineering-i2<br/>(see infra/iam.md)"]
  end
  bronze -.->|"planned L04-L05"| silver[("Silver<br/>cleaned, one agreed version")]
  silver -.-> gold[("Gold<br/>star schemas")]
  gold -.->|revenue reports| analysts[Analysts]
  gold -.->|daily demand| ml[ML team]
```

The lakehouse choice is argued in [ADR-0001](adr/0001-target-architecture.md), the bronze layout in [ADR-0002](adr/0002-bronze-layout.md). Bronze was filled once, by hand, with [`ingestion/load_bronze_export.py`](../ingestion/load_bronze_export.py). L03 replaces this with automatic pipelines.

## Layers

| Layer | What lands here | What it guarantees | Who reads it |
|---|---|---|---|
| Bronze | The 7 tables the project needs, from the legacy export, unchanged and stored as text: duplicate orders and the index column are kept. `customer` and `payment_details` are never loaded: they hold passwords and card numbers. | Nothing that arrived is lost. | Data engineers only, to debug and rebuild silver. Today every member of the shared project can read it: see [infra/iam.md](../infra/iam.md). |
| Silver | Cleaned, typed tables: one row per real order, duplicates removed. | One agreed version of each fact. | The models that build gold. |
| Gold | Star schemas for named questions: `fct_daily_demand`, `dim_product`, `dim_country`, `dim_date`. | Each table answers a named question, at a declared grain. | Analysts and the ML team. |

## Decisions

| ADR | Decision | Status |
|---|---|---|
| [0001](adr/0001-target-architecture.md) | Adopt a lakehouse with bronze, silver and gold layers | Proposed |
| [0002](adr/0002-bronze-layout.md) | Bronze as Parquet (Snappy), partitioned by day | Proposed |

## Change log

| Lesson | What changed |
|---|---|
| L01 | First version: context, target diagram, layer guarantees |
| L02 | The diagram shows what exists: the bucket, its region, its layout, who can read it, and how bronze was filled |