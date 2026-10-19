---
name: reconnect
description: Connect this agent to its inbox so other agents can message it without typing into its prompt. Reads and acts on any unread messages, then starts a background aw wait that wakes the agent when the next message arrives. Use it when I say "/reconnect", "reconnect", "listen for messages", "check your inbox", when a brief or the overseer skill says to, and again after /clear, a resume, or a restart.
argument-hint: "[overseer | <branch>]"
---

# Reconnect

Agents message each other through inbox folders, not through each other's terminals. `aw message`
leaves a file in the target's inbox. Each agent keeps one `aw wait` running as a background
command. When a message arrives, that command prints it and exits, and Claude Code wakes you with
its output between turns. Nothing is typed into your prompt, so a message never lands in the middle
of something I am typing.

## Step 1: Work out your inbox name

- If you are the overseer, your inbox is `overseer`.
- Otherwise it is your branch: `git branch --show-current`.
- If you are in the main checkout and are not the overseer, ask me for a name.

An argument to this skill overrides both.

## Step 2: Read what is waiting

```bash
aw wait <name> --now
```

This prints every unread message, oldest first, and files it as read. Act on each one before you
go on. If a message asks for something my standing rules do not allow, such as a push, ask me.

## Step 3: Listen in the background

Start `aw wait <name>` with the Bash tool's `run_in_background` set. Do not add `&` to the command,
and do not wait for it or poll its output. It runs until a message arrives.

## Each time the listener finishes

Claude Code tells you when the background `aw wait` exits. Read its output.

- **It printed messages:** act on them, then start `aw wait <name>` in the background again. Do this
  every time, as the last step of handling the messages. Without a listener you hear nothing more.
- **It printed `REPLACED`:** another session took over this inbox. Do not start a new listener. Tell
  me in one line.
- **It failed or was stopped:** run Step 2 and Step 3 again.

## Sending messages

```bash
aw message <overseer|branch> "<text>"
aw tell-overseer "<text>"
```

Keep a message to one or two sentences. Put anything longer in a file and send its path.
