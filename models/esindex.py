
import typing as t
from datetime import datetime

import pandas as pd
from sqlmesh import ExecutionContext, model
import yaml, os, json
from elasticsearch import Elasticsearch
from elasticsearch.helpers import scan

secrets = yaml.safe_load(os.environ.get("secrets.yaml", open("secrets.yaml").read()))

def fetch_all_documents(url, username, password, index):
    # Create Elasticsearch client
    es = Elasticsearch(url, basic_auth=(username, password))

    # Use the scan helper to efficiently scroll through all documents
    documents = list(scan(es, index=index, query={"query": {"match_all": {}}}))

    return documents

@model(
    "esindex.full_model",
    columns={
        "ConsultationIdentifier": "int",
        "ConsultationApiGatewayId": "text",
        "ConsultationTitle": "text",
        "ConsultationShortDescription": "text",
        "ConsultationShortDescriptionTrimmed": "text",
        "ConsultationStatus": "int",
        "ConsultationAgencyName": "text",
        "ConsultationAgencyNameText": "text",
        "ConsultationEditorName": "text",
        "ConsultationEditorEmail": "text",
        "ConsultationKeywords": "text",
        "ConsultationSubmissionDate": "timestamp",
        "ConsultationCategories": "text",
        "ConsultationRegion": "text",
        "ConsultationPublishDate": "timestamp",
        "ConsultationUrl": "text"
    }
)
def execute(
    context: ExecutionContext,
    start: datetime,
    end: datetime,
    execution_time: datetime,
    **kwargs: t.Any,
) -> pd.DataFrame:
    docs = [doc["_source"] for doc in fetch_all_documents(**secrets["esindex"])]
    return pd.DataFrame(docs)