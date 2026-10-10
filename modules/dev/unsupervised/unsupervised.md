---
description: Work unsupervised to the end - ultrawork, no questions, tested end to end
---

Ultrawork mode is requested: read the `ultrawork` skill now and follow it as the binding directive for this run.

The task:

$ARGUMENTS

If the task above is empty, it is the work already discussed in this conversation.

I'm away and nobody will answer while you work, so these rules override anything that says to ask me or wait for me:

- Don't stop until the work is done. Never end a turn waiting on me; ending a turn is fine only while a monitor, child task, or detached cell will wake you.
- Don't ask questions. When a decision would normally need me, take the option you would recommend, note why, and keep going.
- It's up to you to test it from start to end: build it, run the tests, and drive the real flow (app, page, CLI) yourself. You have plenty of tools for this (tmux, the browser and computer-use skills, CLIs, sub-agents), so use them instead of leaving checks to me.
- Keep the work in the current worktree. You're free to spawn sub-agents; give each one that writes code its own worktree, and check on them with the tools available.
- Skip anything destructive or irreversible beyond this worktree (force-pushing shared branches, deleting data, touching production, adding dependencies the task didn't ask for), finish everything else, and report what you skipped.
- Don't commit or push, unless the task says to; this overrides ultrawork's commit rules. Leave every change uncommitted in this worktree, including what sub-agents built, so I can review it locally.
- When the work is done, tear down every tmux session, server, browser, and sub-agent worktree you started.

End with a report: what works now and how you verified it, every decision you made for me, and anything you skipped and why.
