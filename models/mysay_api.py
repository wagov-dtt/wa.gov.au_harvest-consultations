from datetime import datetime
import typing as t
import pandas as pd
import requests
from sqlmesh import ExecutionContext, model

from common import secrets

def get_projects(url: str, username: str, password: str) -> list:
    # Authenticate and fetch projects
    auth_token = requests.post(f"{url}/tokens", json={"data": {"attributes": {
                               "login": username, "password": password}}}).json()['data']['attributes']['token']
    return requests.get(f"{url}/projects", params={"per_page": 10000}, headers={"Authorization": f"Bearer {auth_token}"}).json()["data"]


@model(
    "mysay.api",
    columns={
        "id": "text", "type": "text", "attributes": "json",
        "relationships": "json", "links": "json"
    }
)
def execute(context: ExecutionContext, start: datetime, end: datetime, execution_time: datetime, **kwargs: t.Any) -> pd.DataFrame:
    return pd.concat([pd.DataFrame(get_projects(**config)) for config in secrets["mysay"]])
