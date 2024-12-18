from datetime import datetime
from typing import Any
import pandas as pd
import os, requests, yaml
from sqlmesh import ExecutionContext, model

# extract configs from env
configs = yaml.safe_load(os.environ["SECRETS_YAML"]).get("mysay", [])

def load(config: dict) -> pd.DataFrame:
    # Function to use a config to return a dataframe
    url, username, password = config["url"], config["username"], config["password"]
    try:
        auth_token = requests.post(f"{url}/tokens", json={"data": {"attributes": {
                               "login": username, "password": password}}}).json()['data']['attributes']['token']
        result = requests.get(f"{url}/projects", params={"per_page": 10000}, headers={"Authorization": f"Bearer {auth_token}"}).json()["data"]
    except Exception as e:
        print(e)
        result = []
    return pd.DataFrame(result)

@model(
    "mysay.api",
    columns={
        "id": "text", "type": "text", "attributes": "json",
        "relationships": "json", "links": "json"
    }
)
def execute(context: ExecutionContext, start: datetime, end: datetime, execution_time: datetime, **kwargs: Any) -> pd.DataFrame:
    # Iterate over each config and load the data into a DataFrame
    dataframes = map(load, configs)
    # concat all results
    result = pd.concat(dataframes)
    return result