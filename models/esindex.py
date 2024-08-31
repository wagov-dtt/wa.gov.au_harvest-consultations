from datetime import datetime
import typing as t
import pandas as pd
from sqlmesh import ExecutionContext, model
from elasticsearch import Elasticsearch
from elasticsearch.helpers import scan
from common import secrets

def fetch_index(url: str, username: str, password: str, index: str) -> list:
    # Fetch all documents from Elasticsearch index
    es_client = Elasticsearch(url, basic_auth=(username, password))
    return [doc["_source"] for doc in scan(es_client, index=index, query={"query": {"match_all": {}}})]

@model(
    "esindex.full_model",
    columns={
        "ConsultationIdentifier": "int", "ConsultationApiGatewayId": "text",
        "ConsultationTitle": "text", "ConsultationShortDescription": "text",
        "ConsultationShortDescriptionTrimmed": "text", "ConsultationStatus": "int",
        "ConsultationAgencyName": "text", "ConsultationAgencyNameText": "text",
        "ConsultationEditorName": "text", "ConsultationEditorEmail": "text",
        "ConsultationKeywords": "text", "ConsultationSubmissionDate": "timestamp",
        "ConsultationCategories": "text", "ConsultationRegion": "text",
        "ConsultationPublishDate": "timestamp", "ConsultationUrl": "text"
    }
)
def execute(context: ExecutionContext, start: datetime, end: datetime, execution_time: datetime, **kwargs: t.Any) -> pd.DataFrame:
    # Fetch data and return as DataFrame
    return pd.DataFrame(fetch_index(**secrets["esindex"]))