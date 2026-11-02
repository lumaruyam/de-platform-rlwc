# IAM on the bronze bucket

Bucket: `gs://data-engineering-i2-group2`. Checked on 2026-11-02 with:

    gcloud storage buckets get-iam-policy gs://data-engineering-i2-group2

## Bindings on the bucket

| Principal | Role | Scope | Why |
|---|---|---|---|
| `projectOwner` and `projectEditor` of `data-engineering-i2` | `roles/storage.legacyBucketOwner` | Bucket | Default binding added by Google when the bucket was created. |
| `projectViewer` of `data-engineering-i2` | `roles/storage.legacyBucketReader` | Bucket | Default binding: viewers can list the bucket. |
| `projectOwner` and `projectEditor` of `data-engineering-i2` | `roles/storage.legacyObjectOwner` | Objects in the bucket | Default binding: owners and editors can read, write and delete files. |
| `projectViewer` of `data-engineering-i2` | `roles/storage.legacyObjectReader` | Objects in the bucket | Default binding: viewers can read files. |

Uniform bucket-level access is on, so access is set for the whole bucket, not file by file. Public access prevention is enforced: nobody outside the project can read it.

## Known gaps

- **The project is shared by the whole class.** Every student with a role on `data-engineering-i2` gets access to this bucket through the project, not only our group. Roles granted at project level do not show in the bucket policy above, and we cannot read the project's IAM policy: we do not have the permission. This is not least privilege.
- **No read-only access for the ML team yet.** The ML team only needs to read. The plan is a service account with `roles/storage.objectViewer` on this bucket only. We have not created it yet.

## What would fix it

A project per group would limit access to our four members. Inside the project, read access for consumers would go through a read-only service account, never through project roles.