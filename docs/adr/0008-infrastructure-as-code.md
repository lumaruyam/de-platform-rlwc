# ADR-0008: Adopt the existing bucket and datasets in Terraform with import blocks, state in our bucket

- **Status:** proposed
- **Date:** 2026-11-06
- **Author:** Rania Mehria
- **Lesson:** L08

## Context

The bucket (L02) and three datasets (L04, L05) were created by hand. Their settings live in the
console and in our documents. From L08, changes must go through code and be reviewed.
The bucket holds the data: re-creating it is not an option.

## Options considered

1. **Keep clicking in the console** and document each change.
2. **Write new Terraform resources** with new names, and move the data.
3. **Describe the existing resources and adopt them with `import` blocks.**

## Criteria

| Criterion | 1. Console | 2. New resources | 3. Import |
|---|---|---|---|
| Changes reviewed in a pull request | No | Yes | Yes |
| Risk to existing data | None | Copy and switch | None |
| Proof that code matches reality | No | - | `plan` shows 0 to change |
| Effort | None | High | Low |

## Decision

Option 3. `infra/`: Terraform 1.17.1, Google provider `~> 8.4`.

- `storage.tf`: the bucket with every L02 setting (Standard, public access blocked, uniform access,
  7-day soft delete, bronze lifecycle, never deleted), and `prevent_destroy`.
- `bigquery.tf`: `group2_wh`, `group2_silver`, `group2_gold`, `delete_contents_on_destroy = false`.
- **Remote state** in our bucket, prefix `terraform/state`, outside `bronze/` so the lifecycle never moves it.
- CI: `.github/workflows/terraform-plan.yml` runs fmt and validate on every pull request touching
  `infra/`, and plan when a `GCP_CREDENTIALS` secret exists.

Result: plan "4 to import, 0 to add, 0 to change, 0 to destroy", apply wrote only the state,
next plan "No changes".

## Consequences

- The first plan wanted to remove the bucket's encryption enforcement rules, set by Google. We do not
  manage them: `ignore_changes = [encryption]`.
- State and data share one bucket: `prevent_destroy` protects both, but losing the bucket loses the state.
- CI cannot run `plan` yet: creating a service account needs admin rights on the shared class project.
- Labels (L09) and access grants (L10) were then added through this code.
