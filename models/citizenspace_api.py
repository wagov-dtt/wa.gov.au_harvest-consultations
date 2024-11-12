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
def execute(context: ExecutionContext, start: datetime, end: datetime, execution_time: datetime, **kwargs: t.Any) -> pd.DataFrame:
    return pd.concat([pd.DataFrame(load(**config)) for config in secrets["citizenspace"]])
