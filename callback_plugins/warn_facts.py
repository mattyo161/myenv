"""Surface task-emitted messages as real Ansible [WARNING] lines.

Ansible has no built-in way for an ordinary task to emit a warning that lands
in the highlighted warning channel (and the end-of-run summary) without also
failing. This callback bridges that gap: any task that sets a fact named
``callback_warnings`` — a string or a list of strings, typically via
ansible.builtin.set_fact — has those messages printed through the warning
channel. The dotfiles role uses it to flag files changed outside chezmoi.

The plugin is inert for every other task, so it is safe to enable globally.
"""

from __future__ import annotations

from ansible.plugins.callback import CallbackBase


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "notification"
    CALLBACK_NAME = "warn_facts"
    # Required so a non-stdout callback is loaded via `callbacks_enabled`.
    CALLBACK_NEEDS_ENABLED = True

    def v2_runner_on_ok(self, result):
        facts = result._result.get("ansible_facts") or {}
        messages = facts.get("callback_warnings")
        if not messages:
            return
        if not isinstance(messages, (list, tuple)):
            messages = [messages]
        for message in messages:
            if message:
                self._display.warning(str(message))
