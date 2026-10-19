---
name: handoff
description: Finish a piece of work that an overseer briefed out. Writes a handoff file next to the brief, saying what was done, the PR and branch state, what is still open and what is needed, then messages the overseer. Use it when a brief tells me to run /handoff, when I say "hand off", "handoff", "report back to the overseer", or when the work a brief describes is done or blocked.
---

# Handoff

You are a worker that the overseer started from a brief. This skill reports your state back so the
overseer can update the plan without reading your session. Run it when the brief's work is done,
and also when you are blocked and need a decision.

## Step 1: Find the brief

The prompt that started you names the brief's path. If you cannot find that prompt, look in
`~/.claude/overseer/*/briefs/` for the file named after the current branch, with each `/` in the
branch name replaced by `--`. If neither gives a brief, ask me where it is.

The handoff file goes in the sibling folder: `.../<repo>/handoffs/<branch-slug>.md`.

## Step 2: Gather the facts

```bash
git branch --show-current
git status --short
git log --oneline <base>..HEAD
git rev-list --count @{upstream}..HEAD 2>/dev/null   # unpushed commits; fails if there is no upstream
gh pr view --json number,url,state,isDraft,reviewDecision 2>/dev/null
```

`<base>` is the base branch the brief names.

## Step 3: Write the handoff

Overwrite the handoff file with these sections. Keep it under a screen.

- **Status:** done, blocked, or needs a decision, and the timestamp.
- **Branch:** name, base, and whether every commit is pushed.
- **PR:** number and URL, draft or ready, and review state. Say "none" if there is no PR.
- **What changed:** two to five lines on what the work did.
- **Open:** anything left undone, failing checks and unresolved review threads.
- **Needs:** the decision or action you need, and from whom: the overseer or me.

State facts. Do not repeat the brief.

## Step 4: Tell the overseer

Leave the overseer one line:

```bash
aw tell-overseer "Handoff ready for <branch>: <status>. <handoff path>"
```

This leaves a file in the overseer's inbox, and its listener wakes it. Tell me the handoff path as
well, in one line.

Then stop and wait. Keep your own listener running, as `/reconnect` describes, so the overseer can
send the next instruction.
