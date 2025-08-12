from enum import Enum


class Environment(Enum):
    """
    Enum for different deployment environments.
    """

    LOCALHOST = "localhost"
    INTEGRATION = "int"
    STAGE = "stage"
    PRODUCTION = "prod"


def get_base_url(env: Environment) -> str:
    """Get base URL based on environment."""
    match env:
        case Environment.INTEGRATION:
            return "https://assisted-chat.api.integration.openshift.com"
        case Environment.STAGE:
            return "https://assisted-chat.api.stage.openshift.com"
        case Environment.PRODUCTION:
            return "https://assisted-chat.api.openshift.com"
        case Environment.LOCALHOST:
            return "http://localhost:8090"
