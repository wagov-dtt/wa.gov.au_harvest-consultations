import requests, os

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


if __name__ == "__main__":
    base_url = os.getenv("MYSAY_URL")
    username = os.getenv("MYSAY_USERNAME")
    password = os.getenv("MYSAY_PASSWORD")

    try:
        headers = authenticate(base_url, username, password)
        projects = get_projects(base_url, headers)
        print("Projects retrieved successfully:")
        print(projects)
    except Exception as e:
        print(f"An error occurred: {e}")