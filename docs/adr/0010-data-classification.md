# ADR-0010: Grant access by column class, enforced with policy tags, and mask free text before silver

- **Status:** proposed
- **Date:** 2026-11-06
- **Author:** Rania Mehria
- **Lesson:** L10

## Context

The warehouse holds 34 columns in 7 tables (`docs/governance.md`). 11 of them identify or link to a
person: 5 address and phone columns that reach a person on their own, and 6 ids (`buyer_id`, `c_id`,
`address_id`, `payment_id`). Three more are free text: in 111,322 reviews we found 7 e-mails and
86 phone-like numbers on 2026-11-06, and we cannot tell what else people wrote.

Three kinds of reader: analysts and the ML team, who need product, country, day and units, never a
person; the group's data engineers; the pipeline. Today everyone in the shared class project can
read every dataset (`infra/iam.md`), and we cannot change project roles (403 in steps 6 and 8).

Tables keep arriving: 7 in step 2, 3 more copies through the extractor and Airbyte in step 3.
A rule that has to be rewritten for each new table will be forgotten for one of them.

## Options considered

| Option | For | Against |
|---|---|---|
| 1. Classify columns, grant on the class (policy tags) | One rule per class survives new tables: tag the column, the grant already exists. Auditable: the tag is visible in the schema. | Two things to reason about (dataset grant and tag grant). A tag on a table nobody restricted protects nothing, silently. Needs Data Catalog rights. |
| 2. A view per consumer | Exactly the columns each consumer needs. No tagging. | One view per consumer to maintain forever, and the raw table is still readable by whoever has dataset access. |
| 3. A dataset per sensitivity level | Simple, coarse, hard to get wrong: grant the dataset, done. | The same data copied twice and kept in step; we already have 3 copies of orders. |
| 4. Trust people not to query it | Nothing to build. | Not a control. The audit log would prove it the first time someone looks. |

## Criteria

| Criterion | 1. Class + tags | 2. Views | 3. Datasets | 4. Trust |
|---|---|---|---|---|
| Survives a new table or copy | Yes: tag at load | No: new view | Partly: choose the dataset | - |
| Copies of data | None | None | One more | None |
| Readable without the platform's help | Yes, tags in the schema | No | Yes | No |
| Works in our class project today | Tags yes, refusal not provable (see Consequences) | Yes | Grants need admin | Yes |
| Covers free text | No | No | No | No |

None of the four handles free text: a column can be tagged, but the person hides inside the text.

## Decision

Option 1, with two additions that do not depend on admin rights:

- **Classes**: `public`, `internal`, `pii.identifier`, `pii.contact`, `unclassified`, `restricted`, with
  an owner per column (`docs/governance.md`).
- **Enforcement**: taxonomy `group2-data-classification` and policy tag `confidential-direct-pii`
  in Terraform (`infra/policy_tags.tf`), applied to `phone`, `street_address`, `zip`.
- **Free text** is masked before silver (`redact_pii`, checked by a test on every run), and the
  review's author is dropped. The text stays `unclassified`.
- **Minimisation**: gold carries no person, so analysts and the ML team never need a tagged column.
  `infra/access.tf` grants them gold only, once project roles allow it.

We would switch to option 3 if the tags could not be enforced for a whole year, or if a consumer
needed raw text: a separate dataset would at least be one clear grant.

## Consequences

- **The tag is in place but not proven.** Our account can still read the tagged columns: the class
  project gives every member a broad role that includes fine-grained read. A refusal needs an
  identity without that role, which we cannot create. Written as a gap in `docs/governance.md`.
- Before tagging we checked the readers: only `stg_shipping_details` reads the table, and it selects
  `address_id` and `country`. The pipeline did not break (PASS=57).
- Regexes catch formats, not meaning: a name in a review stays. Some long product numbers may be masked.
- A new table with a phone column is protected only if someone tags it. The tag list lives in
  `scripts/apply_policy_tags.py`; a new source must update it.
- Erasure is easier because gold holds nobody: only bronze, `group2_wh` and silver need it
  (`docs/runbooks/erasure.md`).
