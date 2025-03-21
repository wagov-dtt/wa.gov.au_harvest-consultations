from datetime import datetime
from typing import Any
import pandas as pd
import os, requests, json
from sqlmesh import ExecutionContext, model

# extract configs from env
configs = json.loads(os.environ["HARVEST_PORTALS"]).get("citizenspace", [])

def load(url: str) -> pd.DataFrame:
    # Function to use a config to return a dataframe
    try:
        result = requests.get(f"{url}/api/2.3/json_search_results?fields=extended").json()
    except Exception as e:
        print(e)
        result = []
    return pd.DataFrame(result)


@model(
    "citizenspace.api",
    columns={
        "status": "text",
        "startdate": "text",
        "type_string": "text",
        "enddate": "text",
        "title": "text",
        "url": "text",
        "overview": "text",
        "visibility": "text",
        "dept": "text",
        "participate_url": "text",
        "department": "text",
        "progress": "text",
        "type": "text",
        "id": "text"
    }
)

def execute(context: ExecutionContext, start: datetime, end: datetime, execution_time: datetime, **kwargs: Any) -> pd.DataFrame:
    # Iterate over each config and load the data into a DataFrame
    dataframes = map(load, configs)
    # concat all results
    result = pd.concat(dataframes)
    return result