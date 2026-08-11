# Running this pipeline in GitHub Copilot (VS Code)

Two ways to drive it: **prompt files** (`/01-analyze` style slash commands) and
**custom agents** (pick a persona from the agent dropdown). Both live under
`.github/` and both are discovered **only at the workspace-root `.github/`
folder**. That is the #1 reason the slash commands don't show up — see below.

## ⚠️ Fix "the `/` menu doesn't show `/01-analyze`"

VS Code looks for `.github/prompts/` and `.github/agents/` at the **root of the
folder you opened**. If you opened the parent `teradata2snowflake/`, then this
pipeline's `.github/` is one level down (`teradata2snowflake/snowflake2snowflake/.github/`)
and Copilot won't find it.

**Do one of these:**

1. **Open this folder as the workspace root (simplest).**
   `File → Open Folder…` → select **`snowflake2snowflake`** (not the parent).
   Now `.github/prompts`, `.github/agents`, and `.vscode/settings.json` all
   resolve. Trust the workspace when prompted.

2. **Or keep the parent open and point VS Code at the subfolder.** Add to the
   parent's `.vscode/settings.json`:

   ```json
   {
     "chat.promptFiles": true,
     "chat.promptFilesLocations": { "snowflake2snowflake/.github/prompts": true },
     "chat.agentFilesLocations":  { "snowflake2snowflake/.github/agents":  true }
   }
   ```

After either, run **Developer: Reload Window** (Command Palette). Prerequisites:
the **GitHub Copilot** and **GitHub Copilot Chat** extensions installed and
signed in, and a recent VS Code (custom agents need 1.104+).

### Verify discovery

Right-click in the Chat view → **Diagnostics** (the chat-customization
diagnostics view). It lists every prompt file, instruction file, and custom
agent that loaded, plus any errors. Your five prompts and six agents should
appear.

## Option A — Prompt files (slash commands)

Set the chat to **Agent** mode, then in the chat input type `/` and pick the
stage (or just type the name):

```
/01-analyze   00_input/ins_wrk_dc_priority_snowflake.sql
/03-fix       00_input/ins_wrk_dc_priority_snowflake.sql
/04-validate  03_fix/output/ins_wrk_dc_priority_snowflake_fixed.sql
/05-report    ins_wrk_dc_priority
/06-explain   ins_wrk_dc_priority
```

If `/name` still doesn't autocomplete, run **Chat: Run Prompt** from the Command
Palette and pick the file, or open the `.prompt.md` file and press the ▶ (play)
button in the editor title bar.

## Option B — Custom agents (recommended — the agentic flow)

Open the **agent dropdown** at the top of the Chat view (where it says *Agent /
Ask / Edit*). Alongside the built-ins you'll see:

| Agent | Does |
|---|---|
| **s2s-remediate** | Orchestrates the whole pipeline via subagents — start here |
| **s2s-analyze** | Stage 1 audit only |
| **s2s-fix** | Stage 3 fix only |
| **s2s-validate** | Stage 4 sqlglot validation only |
| **s2s-report** | Stage 5 report only |
| **s2s-explain** | Stage 6 semantic explanation + embed into final SQL |

Typical use:

1. Pick **s2s-remediate** and say: *"Remediate
   `00_input/ins_wrk_dc_priority_snowflake.sql`. Run all stages."*
   It calls the stage subagents in order, using `02_rules/` and the Teradata
   original as ground truth.
2. Or step through manually: pick **s2s-analyze**, review, then use the
   **handoff button** that appears after the reply (*"Fix it (Stage 3)"*) to move
   to **s2s-fix** with context carried over, and so on through validate → report
   → explain.

Each agent restricts its own tools (e.g. `s2s-analyze` can't edit the SQL;
`s2s-validate` can run the validator task), which keeps the stages honest.

> Tip: type `/agents` in the chat input to open **Configure Custom Agents** and
> confirm all six are enabled/visible.

## What each mechanism reads

- `.github/copilot-instructions.md` — loaded on **every** request (the ICM rules).
- `.github/prompts/*.prompt.md` — the five stage slash commands.
- `.github/agents/*.agent.md` — the six custom agents (this file's Option B).
- `02_rules/*.md` — the fix + semantic rules the agents must read each run.
- `.vscode/tasks.json` — **S2S: Validate fixed SQL** and **S2S: Annotate SQL with
  semantic comments** (agents call these via the run-task tool).
