"""CitizenSpace API harvester."""

import pandas as pd
import requests


def harvest(urls: list[str]) -> pd.DataFrame:
    """Harvest consultations from CitizenSpace portals.
    
    Args:
        urls: List of CitizenSpace portal URLs
        
    Returns:
        DataFrame with columns: id, title, status, startdate, enddate, url, etc.
    """
    result = []
    
    for url in urls:
        try:
            resp = requests.get(
                f"{url}/api/2.3/json_search_results?fields=extended",
                timeout=10
            )
            consultations = resp.json()
            result.extend(consultations)
        except Exception as e:
            print(f"Error harvesting {url}: {e}")
    
    return pd.DataFrame(result) if result else pd.DataFrame()
