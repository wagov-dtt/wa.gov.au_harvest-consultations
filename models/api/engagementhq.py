"""EngagementHQ API harvester."""

import re
import pandas as pd
import requests


def harvest(urls: list[str]) -> pd.DataFrame:
    """Harvest consultations from EngagementHQ portals.
    
    Args:
        urls: List of EngagementHQ portal URLs
        
    Returns:
        DataFrame with columns: id, name, description, state, published-at, url, etc.
    """
    result = []
    
    for url in urls:
        try:
            # Extract auth token from page
            page = requests.get(url, timeout=10).text
            auth_token = re.findall(r'data-thunder="([^"]*)"', page)
            if not auth_token:
                print(f"No auth token found for {url}")
                continue
            
            auth_token = auth_token[0]
            
            # Fetch projects
            resp = requests.get(
                f"{url}/api/v2/projects",
                params={"per_page": 10000},
                headers={"Authorization": f"Bearer {auth_token}"},
                timeout=10
            )
            projects = resp.json().get("data", [])
            
            for row in projects:
                row.update(row.pop("attributes", {}))
                row["url"] = row.get("links", {}).pop("self", url)
            
            result.extend(projects)
        except Exception as e:
            print(f"Error harvesting {url}: {e}")
    
    return pd.DataFrame(result) if result else pd.DataFrame()
