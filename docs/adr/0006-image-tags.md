# ADR-0006: Tag images with the git commit, never latest, keep the last 5 versions

- **Status:** proposed
- **Date:** 2026-11-06
- **Author:** Rania Mehria
- **Lesson:** L06

## Context

Each job family has its own image, pinned and non-root (`docs/packaging.md`): `group2-ingestion`
and `group2-dbt`. Airflow (L07) must run exactly the code that was tested, and anyone must be
able to pull it. Images live in the class registry `dataeng` (europe-west1). We cannot create our
own registry (`artifactregistry.repositories.create` denied, 2026-11-06), and `dataeng` has no
immutable tags and no cleanup policy, which we cannot add.

## Options considered

1. **`latest`**, overwritten on every build.
2. **Version numbers by hand** (`0.1`, `0.2`).
3. **The git commit** (`4219782`), with a script that refuses `latest`, refuses a dirty tree, and
   refuses a tag that already exists.

## Criteria

| Criterion | 1. latest | 2. Version by hand | 3. Git commit |
|---|---|---|---|
| A tag always means the same image | No | Only if nobody forgets | Yes, enforced by the script |
| From a tag, find the exact code | No | Needs a changelog | `git show 4219782` |
| A rollback is one tag change | No | Yes | Yes |
| Works without registry settings | Yes | Yes | Yes |

## Decision

Option 3. `scripts/release_images.sh` builds and pushes both images as
`europe-west1-docker.pkg.dev/data-engineering-i2/dataeng/group2-<job>:<commit>`.
It refuses `latest`, uncommitted changes in `ingestion/` or `dbt/`, and an existing tag.

**Retention:** keep the 5 most recent versions of each image; delete older versions once they are
also more than 30 days old. `scripts/prune_images.py` is the policy (dry run by default, `--apply` to delete).

## Consequences

Evidence (2026-11-06):

- Released `4219782` for both images. A second release of `4219782` is refused ("already exists");
  `latest` is refused; a release with uncommitted changes is refused.
- `prune_images.py`: 3 versions per image (the tagged image and 2 build attestations), all kept.
- Clean reproduction: local images deleted, both pulled from the registry, `dbt build` from the
  pulled image: PASS=57 WARN=1 ERROR=0 (`docs/reproduce.md`).
- The Airflow DAG runs `group2-<job>:4219782`, not a local tag.

Costs: immutability is a convention we enforce, not a registry setting; someone pushing by hand
could still overwrite a tag. Each release needs a commit first. Retention runs when we run it,
not on a schedule (it could become an Airflow task).
