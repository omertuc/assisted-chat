from pydantic import BaseModel, Field
from datetime import datetime


class Message(BaseModel):
    role: str = Field(
        description="The role of the message sender, either 'user' or 'assistant'."
    )
    content: str = Field(
        description="The content of the message, which can be text or other data."
    )

    def __init__(self, **data):
        super().__init__(**data)

    def __str__(self):
        return f"{self.role}: {self.content}"


class Conversation(BaseModel):
    conversation_id: str = Field(
        description="The unique identifier of the conversation."
    )
    created_at: datetime = Field(
        description="The timestamp when the conversation was created.",
    )
    last_message_at: datetime = Field(
        description="The timestamp of the last message in the conversation.",
    )
    message_count: int = Field(
        description="The total number of messages in the conversation.",
    )
    last_used_model: str = Field(
        description="The model used for the last message in the conversation.",
    )
    last_used_provider: str = Field(
        description="The provider used for the last message in the conversation.",
    )

    def __init__(self, **data):
        if "created_at" in data:
            data["created_at"] = datetime.fromisoformat(
                data["created_at"].replace("Z", "+00:00")
            )
        if "last_message_at" in data:
            data["last_message_at"] = datetime.fromisoformat(
                data["last_message_at"].replace("Z", "+00:00")
            )
        super().__init__(**data)
