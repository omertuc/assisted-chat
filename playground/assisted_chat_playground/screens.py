import os
import asyncio
from textual.app import ComposeResult
from textual.widgets import (
    DataTable,
    Static,
    Header,
    Footer,
    Label,
    TabbedContent,
    TabPane,
    TextArea,
    Markdown,
    Button,
    LoadingIndicator,
)
from textual.screen import Screen
from textual.containers import VerticalScroll, Horizontal, Vertical
from textual import events
from .models import Conversation
from .api import fetch_system_prompt, fetch_models, fetch_messages
from .env import Environment
import litellm


class MessageDetailScreen(Screen):
    """Screen to display messages from a conversation."""

    def __init__(self, conversation: Conversation, env: Environment, **kwargs):
        super().__init__(**kwargs)
        self.conversation = conversation
        self.env = env
        self.messages = []
        self.system_prompt = ""
        self.models = []
        self.selected_message_index = None
        self.replay_view_active = False
        self.replay_counter = 0

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(
            f"Conversation: {self.conversation.conversation_id[:8]}... (Press Esc to go back)",
            id="conversation-header",
        )
        with Vertical():
            horizontal_container = Horizontal()
            horizontal_container.styles.border_bottom = ("solid", "gray")
            with horizontal_container:
                with Vertical():
                    yield Static("[bold]System prompt[/bold]", id="system-prompt-title")
                    tabs = TabbedContent(id="system-prompt-tabs")
                    tabs.styles.width = "100%"
                    yield tabs
                with Vertical():
                    yield Static("[bold]Model selection[/bold]", id="models-title")
                    table = DataTable(id="models-table")
                    table.styles.width = "100%"
                    table.styles.height = "100%"
                    yield table
            yield horizontal_container

            # Selected message controls
            with Horizontal(id="selected-controls") as selected_controls:
                selected_controls.styles.display = "none"
                selected_controls.styles.height = 3
                selected_controls.styles.padding = (0, 1)
                yield Button(
                    "Replay conversation up to this message", id="replay-button"
                )

            # Conversation area with horizontal split
            with Horizontal(id="conversation-horizontal"):
                # Main conversation view
                with Vertical(id="main-view"):
                    yield VerticalScroll(id="messages-container")

                # Replay view (initially hidden)
                with Vertical(id="replay-view") as replay_view:
                    replay_view.styles.display = "none"
                    replay_view.styles.width = "50%"
                    replay_view.styles.border_left = ("solid", "gray")
                    yield Static("[bold]Replay View[/bold]", id="replay-header")
                    yield VerticalScroll(id="replay-messages-container")
        yield Footer()

    def on_mount(self) -> None:
        """Load all data when screen is mounted."""
        self.load_system_prompt()
        self.load_models()
        self.load_messages()

    def load_system_prompt(self) -> None:
        """Fetch and display system prompt."""
        try:
            self.system_prompt = fetch_system_prompt(self.env)
            tabs = self.query_one("#system-prompt-tabs", TabbedContent)

            original_viewer = Markdown(self.system_prompt, id="original-prompt-viewer")
            original_viewer.styles.width = "100%"
            original_pane = TabPane("Original", original_viewer)
            tabs.add_pane(original_pane)

            edited_text = TextArea(text=self.system_prompt, id="edited-prompt-text")
            edited_text.styles.width = "100%"
            edited_text.styles.min_height = 10
            edited_pane = TabPane("Edited", edited_text)
            tabs.add_pane(edited_pane)

        except Exception as e:
            tabs = self.query_one("#system-prompt-tabs", TabbedContent)
            error_label = Label(f"Error loading system prompt: {e}")
            error_pane = TabPane("Error", error_label)
            tabs.add_pane(error_pane)

    def load_models(self) -> None:
        """Fetch and display models table."""
        try:
            self.models = fetch_models(self.env)
            table = self.query_one("#models-table", DataTable)
            table.cursor_type = "row"
            table.add_columns("Provider", "Model", "Type")

            default_row_index = None
            for i, model in enumerate(self.models):
                provider_id = model.get("provider_id", "Unknown")
                model_id = model.get("provider_resource_id", "Unknown")

                # Determine if this is the original model used in the conversation
                is_original = (
                    provider_id == self.conversation.last_used_provider
                    and model_id == self.conversation.last_used_model
                )
                model_type = "Original" if is_original else "Alternative"

                table.add_row(provider_id, model_id, model_type)

                # Check if this matches the conversation's last used model/provider
                if is_original:
                    default_row_index = i

            # Select the default row if found
            if default_row_index is not None:
                table.move_cursor(row=default_row_index)

        except Exception as e:
            table = self.query_one("#models-table", DataTable)
            table.add_columns("Error")
            table.add_row(f"Error loading models: {e}")

    def load_messages(self) -> None:
        """Fetch and display messages."""
        try:
            self.messages = fetch_messages(self.conversation.conversation_id, self.env)
            self.display_messages()
        except Exception as e:
            container = self.query_one("#messages-container", VerticalScroll)
            container.mount(Label(f"Error loading messages: {e}"))

    def display_messages(self) -> None:
        """Display the loaded messages."""
        container = self.query_one("#messages-container", VerticalScroll)

        if not self.messages:
            container.mount(Label("No messages found."))
            return

        for i, msg in enumerate(self.messages):
            if msg.role == "user":
                spacing = "\n"
                message_text = (
                    f"[bold $warning]USER:[/bold $warning]\n{msg.content}{spacing}"
                )
                user_label = Label(message_text, id=f"message-{i}")
                user_label.can_focus = True
                user_label.styles.width = "100%"
                if self.selected_message_index == i:
                    user_label.styles.background = "$surface-lighten-2"
                container.mount(user_label)
            else:
                header_label = Label("[bold $success]ASSISTANT:[/bold $success]")
                markdown_widget = Markdown(msg.content)
                markdown_widget.styles.width = "100%"
                container.mount(header_label)
                container.mount(markdown_widget)

    def select_message(self, index: int) -> None:
        """Select a message and update the display."""
        if self.selected_message_index is not None:
            self.clear_message_highlight(self.selected_message_index)

        if self.selected_message_index == index:
            self.selected_message_index = None
            self.hide_selected_controls()
        else:
            self.selected_message_index = index
            self.highlight_message(index)
            self.show_selected_controls()

    def highlight_message(self, index: int) -> None:
        """Add highlight to a message."""
        user_widget = self.query_one(f"#message-{index}")
        user_widget.styles.background = "blue 20%"

    def clear_message_highlight(self, index: int) -> None:
        """Clear highlight from a message."""
        user_widget = self.query_one(f"#message-{index}")
        user_widget.styles.background = "transparent"

    def show_selected_controls(self) -> None:
        """Show the controls for selected message."""
        controls = self.query_one("#selected-controls")
        controls.styles.display = "block"

    def hide_selected_controls(self) -> None:
        """Hide the controls for selected message."""
        controls = self.query_one("#selected-controls")
        controls.styles.display = "none"

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button presses."""
        if event.button.id == "replay-button":
            self.start_replay()

    def start_replay(self) -> None:
        """Start the replay process."""
        if self.selected_message_index is None:
            return

        # Show replay view
        replay_view = self.query_one("#replay-view")
        replay_view.styles.display = "block"

        # Adjust main view width
        main_view = self.query_one("#main-view")
        main_view.styles.width = "50%"

        self.replay_view_active = True

        # Show messages up to selected index immediately
        self.replay_counter += 1
        self.display_replay_messages()

        # TODO: This is where the actual replay action would be triggered
        # The loading indicator will remain until the action completes

    def display_replay_messages(self) -> None:
        """Display messages up to the selected point in replay view."""
        container = self.query_one("#replay-messages-container")

        # Clear existing content completely
        try:
            container.remove_children()
        except Exception:
            pass

        if not self.messages or self.selected_message_index is None:
            container.mount(Label("No messages to replay."))
            return

        # Show messages up to and including the selected message
        messages_to_show = self.messages[: self.selected_message_index + 1]

        for i, msg in enumerate(messages_to_show):
            if msg.role == "user":
                spacing = "\n"
                message_text = (
                    f"[bold $warning]USER:[/bold $warning]\n{msg.content}{spacing}"
                )
                user_label = Label(
                    message_text, id=f"replay-message-{self.replay_counter}-{i}"
                )
                user_label.styles.width = "100%"
                container.mount(user_label)
            else:
                header_label = Label("[bold $success]ASSISTANT:[/bold $success]")
                markdown_widget = Markdown(msg.content)
                markdown_widget.styles.width = "100%"
                container.mount(header_label)
                container.mount(markdown_widget)

        # Add loading indicator and start LLM completion
        loading_indicator = LoadingIndicator(id=f"replay-loading-{self.replay_counter}")
        loading_indicator.styles.height = 3
        loading_indicator.styles.margin = (1, 0)
        container.mount(loading_indicator)

        # Start the LLM completion process
        self.start_llm_completion(container, loading_indicator)

    def start_llm_completion(self, container, loading_indicator) -> None:
        """Start the LLM completion process in the background."""
        # Schedule the async completion
        asyncio.create_task(self.complete_with_llm(container, loading_indicator))

    async def complete_with_llm(self, container, loading_indicator) -> None:
        """Complete the conversation using LLM."""
        try:
            # Prepare messages for LLM
            messages_to_show = self.messages[: self.selected_message_index + 1]

            # Convert to LLM format and prepend system prompt
            messages = []

            # Get system prompt from the text area
            try:
                edited_text = self.query_one("#edited-prompt-text", TextArea)
                system_prompt = edited_text.text
            except Exception:
                system_prompt = self.system_prompt

            # Add system message
            messages.append({"role": "system", "content": system_prompt})

            # Add conversation messages
            for msg in messages_to_show:
                messages.append({"role": msg.role, "content": msg.content})

            # Get selected model from the table
            table = self.query_one("#models-table", DataTable)
            selected_model = self.models[table.cursor_row]
            # provider_id = selected_model.get("provider_id")
            model_id = selected_model.get("provider_resource_id")
            api_key = os.environ.get("GEMINI_API_KEY")

            # Call LLM
            result = litellm.completion(
                model=model_id,
                api_key=api_key,
                api_base=None,
                messages=messages,
                tools=[],
                tool_choice="auto",
                stream=False,
                temperature=0.0,
            )

            # Remove loading indicator
            loading_indicator.remove()

            # Add the result
            header_label = Label("[bold $success]ASSISTANT (REPLAY):[/bold $success]")
            response_content = result.choices[0].message.content
            markdown_widget = Markdown(response_content)
            markdown_widget.styles.width = "100%"
            container.mount(header_label)
            container.mount(markdown_widget)

        except Exception as e:
            # Remove loading indicator and show error
            loading_indicator.remove()
            error_label = Label(
                f"[bold red]Error during LLM completion:[/bold red]\n{str(e)}"
            )
            error_label.styles.width = "100%"
            container.mount(error_label)

    def on_click(self, event) -> None:
        """Handle click events."""
        # Handle clicks anywhere in the markdown - try broader matching
        if (
            hasattr(event.widget, "id") and event.widget.id == "original-prompt-viewer"
        ) or (
            hasattr(event.widget, "parent")
            and hasattr(event.widget.parent, "id")
            and event.widget.parent.id == "original-prompt-viewer"
        ):
            tabs = self.query_one("#system-prompt-tabs", TabbedContent)
            all_panes = list(tabs.query(TabPane))
            if len(all_panes) > 1:
                tabs.active = all_panes[1].id
            return

        # Handle message clicks
        if (
            hasattr(event.widget, "id")
            and event.widget.id
            and event.widget.id.startswith("message-")
        ):
            message_index = int(event.widget.id.split("-")[1])
            self.select_message(message_index)

    def on_key(self, event: events.Key) -> None:
        """Handle key presses."""
        if event.key == "escape":
            if self.replay_view_active:
                self.close_replay_view()
            else:
                self.app.pop_screen()

    def close_replay_view(self) -> None:
        """Close the replay view and return to normal view."""
        # Hide replay view
        replay_view = self.query_one("#replay-view")
        replay_view.styles.display = "none"

        # Restore main view width
        main_view = self.query_one("#main-view")
        main_view.styles.width = "100%"

        self.replay_view_active = False
