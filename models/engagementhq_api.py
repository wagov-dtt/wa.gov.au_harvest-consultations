from datetime import datetime
from typing import Any
import pandas as pd
import os, re, requests, yaml
from sqlmesh import ExecutionContext, model

# extract configs from env
configs = yaml.safe_load(os.environ["SECRETS_YAML"]).get("engagementhq", [])

def load(url: str) -> pd.DataFrame:
    # Function to use a config to return a dataframe
    result = []
    try:
        auth_token = re.findall(r'data-thunder="([^"]*)"', requests.get(url).text).pop()
        result = requests.get(f"{url}/api/v2/projects", params={"per_page": 10000}, headers={"Authorization": f"Bearer {auth_token}"}).json()["data"]
        for row in result:
            row.update(row.pop("attributes"))
            row["url"] = row["links"].pop("self")
    except Exception as e:
        print(e)
    return pd.DataFrame(result)

@model(
    "engagementhq.api",
    columns={
        "state": "text",
        "published-at": "text",
        "type": "text",
        "name": "text",
        "url": "text",
        "description": "text",
        "visibility-mode": "text",
        "image-url": "text",
        "project-tag-list": "text[]",
        "view-count": "text",
        "id": "text",
        "parent-id": "integer"
    }
)
def execute(context: ExecutionContext, start: datetime, end: datetime, execution_time: datetime, **kwargs: Any) -> pd.DataFrame:
    # Iterate over each config and load the data into a DataFrame
    dataframes = map(load, configs)
    # concat all results
    result = pd.concat(dataframes)
    return result