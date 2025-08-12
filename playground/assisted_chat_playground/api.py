"""
Module to interact with the external API for fetching configurations,
models, conversations, and messages.
"""

import os
from typing import List
import requests
from .models import Message, Conversation
from .env import Environment, get_base_url


def fetch_system_prompt(env: Environment) -> str:
    """Fetch system prompt from /config endpoint."""
    base_url = get_base_url(env)
    response = requests.get(
        f"{base_url}/v1/config",
        timeout=10,
        headers={
            "Authorization": f"Bearer {os.environ['OCM_TOKEN']}",
        },
        allow_redirects=True,
    )
    response.raise_for_status()
    config_data = response.json()
    return config_data.get("customization", {}).get(
        "system_prompt", "No system prompt available."
    )


def fetch_models(env: Environment) -> List[dict]:
    """Fetch available models from /models endpoint."""
    base_url = get_base_url(env)
    response = requests.get(
        f"{base_url}/v1/models",
        timeout=10,
        headers={
            "Authorization": f"Bearer {os.environ['OCM_TOKEN']}",
        },
        allow_redirects=True,
    )
    response.raise_for_status()
    models_data = response.json()
    return models_data.get("models", [])


def fetch_messages(conversation_id: str, env: Environment) -> List[Message]:
    """Fetch messages for a specific conversation."""
    base_url = get_base_url(env)
    response = requests.get(
        f"{base_url}/v1/conversations/{conversation_id}",
        timeout=10,
        headers={
            "Authorization": f"Bearer {os.environ['OCM_TOKEN']}",
        },
        allow_redirects=True,
    )
    response.raise_for_status()
    conversation_data = response.json()

    all_messages = []
    for chat_session in conversation_data.get("chat_history", []):
        for message in chat_session.get("messages", []):
            all_messages.append(
                Message(role=message["type"], content=message["content"])
            )

    return all_messages


def fetch_conversations(env: Environment) -> List[Conversation]:
    """Fetch all conversations from the API."""
    base_url = get_base_url(env)
    response = requests.get(
        f"{base_url}/v1/conversations",
        timeout=10,
        headers={
            "Authorization": f"Bearer {os.environ['OCM_TOKEN']}",
        },
        allow_redirects=True,
    )
    response.raise_for_status()
    return [Conversation(**conv) for conv in response.json()["conversations"]]
