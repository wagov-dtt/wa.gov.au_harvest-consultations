import os
import yaml

secrets = yaml.safe_load(os.environ.get("secrets.yaml")
                         or open("secrets.yaml").read())