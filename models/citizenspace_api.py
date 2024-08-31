from datetime import datetime
import typing as t
import pandas as pd
import requests
from sqlmesh import ExecutionContext, model

from common import secrets

def load(url):
    try:
        return requests.get(url).json()
    except Exception as e:
        print(e)
        return []


@model(
    "citizenspace.api",
    columns={
        "status": "text", "startdate": "date", "enddate": "date",
        "title": "text", "url": "text", "overview": "text", "id": "text"
    }
)
def execute(context: ExecutionContext, start: datetime, end: datetime, execution_time: datetime, **kwargs: t.Any) -> pd.DataFrame:
    return pd.concat([pd.DataFrame(load(**config)) for config in secrets["citizenspace"]])
