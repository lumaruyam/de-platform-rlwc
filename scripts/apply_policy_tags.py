"""Tag the columns that identify a person directly (step 10, docs/governance.md).

The tables are created by SQL, not by Terraform, so the column tags are applied here.
Usage: python apply_policy_tags.py <policy tag resource name>
"""
import sys

from google.cloud import bigquery

TAG = sys.argv[1]
TARGETS = {"data-engineering-i2.group2_wh.shipping_details": {"street_address", "zip", "phone"}}

client = bigquery.Client(project="data-engineering-i2", location="europe-west1")
for table_id, columns in TARGETS.items():
    table = client.get_table(table_id)
    table.schema = [
        bigquery.SchemaField(f.name, f.field_type, mode=f.mode, description=f.description,
                             policy_tags=bigquery.PolicyTagList([TAG]) if f.name in columns else f.policy_tags)
        for f in table.schema
    ]
    client.update_table(table, ["schema"])
    print(table_id, "tagged:", sorted(columns))
