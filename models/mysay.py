
import typing as t
from datetime import datetime

import pandas as pd
from sqlmesh import ExecutionContext, model
import requests, os, yaml

secrets = yaml.safe_load(os.environ.get("secrets.yaml", open("secrets.yaml").read()))

def authenticate(base_url, username, password):
    try:
        response = requests.post(f"{base_url}/tokens", json={
            "data": {"attributes": {"login": username, "password": password}}
        })
        response.raise_for_status()
        token = response.json()['data']['attributes']['token']
        return {'Authorization': f'Bearer {token}'}
    
    except requests.exceptions.RequestException as err:
        print(f"Error retrieving OAuth token: {err}")
        raise Exception('There was an error while retrieving the token')

def get_projects(base_url, headers):
    try:
        params = {'per_page': '999999999999999999'}
        response = requests.get(f"{base_url}/projects", params=params, headers=headers)
        response.raise_for_status()
        return response.json()
    
    except requests.exceptions.RequestException as err:
        raise Exception(f"Error retrieving project data: {err}")


def projects(url, username, password):
    try:
        headers = authenticate(url, username, password)
        projects = get_projects(url, headers)
        print("Projects retrieved successfully:")
        return projects["data"]
    except Exception as e:
        print(f"An error occurred: {e}")

@model(
    "mysay.full_model",
    columns={
        "id": "text",
        "type": "text",
        "description": "text",
        "name": "text",
        "meta_description": "text",
        "meta_keywords": "text",
        "redirect_url": "text",
        "permalink": "text",
        "state": "text",
        "banner_url": "text",
        "restrict_forum_creation": "boolean",
        "description_display_mode": "text",
        "visibility_mode": "text",
        "platform_analytics_tag_list": "array<text>",
        "project_tag_list": "array<text>",
        "image_url": "text",
        "image_caption": "text",
        "image_description": "text",
        "text_wrap_mode": "text",
        "parent_id": "int",
        "subscribers_count": "int",
        "view_count": "int",
        "home_project": "boolean",
        "published_at": "timestamp",
        "forum_topics": "int",
        "survey_tools": "int",
        "banner_caption": "text",
        "widget_resource_count": "int",
        "quick_poll_layout": "text",
        "created_at": "timestamp",
        "updated_at": "timestamp",
        "archival_reason_message": "text",
        "access": "boolean",
        "contribution_count": "int",
        "scheduled_at": "timestamp",
        "is_social_sharing_modal_enabled": "boolean",
        "role_in_current_context": "text",
        "can_contribute": "boolean",
        "site_id": "text",
        "site_type": "text"
    }
)
def execute(
    context: ExecutionContext,
    start: datetime,
    end: datetime,
    execution_time: datetime,
    **kwargs: t.Any,
) -> pd.DataFrame:
    df = pd.concat([pd.DataFrame(projects(**config)) for config in secrets["mysay"]])
    print(df.head())
    return df