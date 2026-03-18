import yaml
from types import SimpleNamespace

def load_config():
    with open("config.yaml") as f:
        data = yaml.safe_load(f)
    return SimpleNamespace(**data)
