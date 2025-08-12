"""A terminal-based application to interact with conversations using Textual."""

import os
from typing import List, cast
from textual.app import App, ComposeResult
from textual.widgets import DataTable, Header, Footer, Select, Button
from textual.containers import Container, Vertical
from textual.screen import Screen
from assisted_chat_playground.models import Conversation
from assisted_chat_playground.api import fetch_conversations
from assisted_chat_playground.env import Environment
from assisted_chat_playground.screens import MessageDetailScreen

if os.environ.get("OCM_TOKEN") is None:
    raise ValueError(
        "OCM_TOKEN environment variable is not set. Please set it to your OCM token."
    )

if os.environ.get("GEMINI_API_KEY") is None:
    raise ValueError(
        "GEMINI_API_KEY environment variable is not set. Please set it to your Gemini API key."
    )


class EnvironmentSelectScreen(Screen):
    """A screen to select the deployment environment to interact with."""

    def compose(self) -> ComposeResult:
        yield Container(
            Header(show_clock=True),
            Vertical(
                Select(
                    [
                        ("localhost", Environment.LOCALHOST),
                        ("integration", Environment.INTEGRATION),
                        ("stage", Environment.STAGE),
                        ("production", Environment.PRODUCTION),
                    ],
                    prompt="Select environment:",
                    value=Environment.INTEGRATION,
                    id="env-select",
                ),
                Button("Connect", id="connect-btn"),
                id="env-container",
            ),
            id="main-container",
        )

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button press events."""
        if event.button.id == "connect-btn":
            env_select_widget = self.query_one("#env-select", Select)
            value = cast(Environment, env_select_widget.value)
            conversations = fetch_conversations(value)
            self.app.push_screen(ConversationApp(conversations, value))


class ConversationApp(Screen):
    """
    A screen to display a list of conversations and allow selection to view details.
    """

    def __init__(self, conversations: List[Conversation], env: Environment, **kwargs):
        super().__init__(**kwargs)
        self.conversations = conversations
        self.env = env

    def on_mount(self) -> None:
        """
        Set up the screen when it is mounted.
        """
        self.title = "Playground"

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        table = DataTable(id="conversations-table")
        table.cursor_type = "row"  # Enable row selection
        table.add_columns(
            "Conversation ID",
            "Created At",
            "Last Message At",
            "Message Count",
            "Last Used Model",
            "Last Used Provider",
        )

        for conv in self.conversations:
            table.add_row(
                conv.conversation_id,
                conv.created_at.isoformat(),
                conv.last_message_at.isoformat(),
                str(conv.message_count),
                conv.last_used_model,
                conv.last_used_provider,
            )

        yield table
        yield Footer()

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        """Handle row selection in the conversations table."""
        row_index = event.cursor_row
        if 0 <= row_index < len(self.conversations):
            selected_conversation = self.conversations[row_index]
            self.app.push_screen(MessageDetailScreen(selected_conversation, self.env))


class PlaygroundApp(App):
    """The main application class for the playground."""

    def on_mount(self) -> None:
        """Set up the main application when it is mounted."""
        self.title = "Playground"
        self.push_screen(EnvironmentSelectScreen())


if __name__ == "__main__":
    app = PlaygroundApp()
    app.run()
