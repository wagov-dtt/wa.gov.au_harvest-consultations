import os
import yaml

secrets = yaml.safe_load(os.environ.get("SECRETS_YAML")
                         or open("secrets.yaml").read())