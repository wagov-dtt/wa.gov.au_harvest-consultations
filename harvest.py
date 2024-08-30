from elasticsearch import Elasticsearch
from elasticsearch.helpers import scan
import json, ibis

con = ibis.connect("duckdb://")

config = {
    "elastic": "dist/esindex.json",
    "mysay": [
        "dist/Mysaytransport-projects.json"
    ],
    "smartsheet": [
        "dist/smartsheet3_dpc.json"
    ],
    "citizenspace": [
        "dist/consult.dwer.json"
    ]
}

def load_current():
    con.read_json("dist/esindex.json", table_name="esindex")
    for table in config["mysay"]
    mysays = [con.read_json(ms) for ms in config["mysay"]]
    smartsheets = [con.read_json(ss) for ss in config["smartsheet"]]


def fetch_all_documents(url, username, password, index):
    # Create Elasticsearch client
    es = Elasticsearch(url, basic_auth=(username, password))

    # Use the scan helper to efficiently scroll through all documents
    documents = list(scan(es, index=index, query={"query": {"match_all": {}}}))

    return documents

if __name__ == "__main__":


    try:
        documents = fetch_all_documents(url, username, password, index)
        print(f"Total documents fetched: {len(documents)}")
        if documents:
            print("Sample of first 5 documents:")
            json.dump(documents, open("dist/esindex.json", "w"), indent=2)
        else:
            print("No documents were fetched.")
    except Exception as e:
        print(f"An error occurred: {str(e)}")