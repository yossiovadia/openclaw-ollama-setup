# OpenClaw + Ollama + Claude Code Setup

Configure OpenClaw to use a remote Ollama instance as the primary model, with automatic delegation of coding tasks to Claude Code CLI. Optionally set up a multi-agent PM/Dev workflow using Agent IRC.

**Author:** Yossi Ovadia ([@yossiovadia](https://github.com/yossiovadia))

## Architecture

```
You (WhatsApp/Telegram/Web UI)
  ↓
OpenClaw Gateway (local Mac/Linux)
  ↓
Ollama (local or remote) ← cheap/free model for general tasks
  ↓
Claude Code CLI ← delegated coding tasks (via coding-agent skill)
```

## Prerequisites

- [OpenClaw](https://openclaw.ai) installed and running
- [Ollama](https://ollama.com) running (local or remote)
- [Claude Code CLI](https://docs.anthropic.com/claude-code) installed (for coding delegation)
- `jq` installed (`brew install jq`)

## Quick Start

```bash
./setup.sh
```

The script will:
1. Detect or ask for your Ollama endpoint
2. List available models and let you choose one
3. Configure `~/.openclaw/openclaw.json`
4. Optionally add Claude Code routing for coding tasks

## Manual Setup

### 1. Configure Ollama Provider

Edit `~/.openclaw/openclaw.json` and add your Ollama provider under `models.providers`:

```json
{
  "models": {
    "mode": "merge",
    "providers": {
      "ollama": {
        "baseUrl": "http://<OLLAMA_IP>:11434/v1",
        "apiKey": "ollama",
        "models": [
          {
            "id": "<MODEL_NAME>",
            "name": "Your Model Name",
            "api": "openai-completions",
            "reasoning": false,
            "input": ["text"],
            "cost": {
              "input": 0,
              "output": 0,
              "cacheRead": 0,
              "cacheWrite": 0
            },
            "contextWindow": 128000,
            "maxTokens": 16384
          }
        ]
      }
    }
  }
}
```

### 2. Set Default Model

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "ollama/<MODEL_NAME>"
      }
    }
  }
}
```

### 3. Add Tool Permissions

**IMPORTANT:** `allow: []` means NO tools allowed. Use `["*"]` to enable all tools:

```json
{
  "tools": {
    "byProvider": {
      "ollama/<MODEL_NAME>": {
        "allow": ["*"]
      }
    }
  }
}
```

### 4. Restart OpenClaw

```bash
openclaw gateway restart
```

### 5. (Optional) Claude Code for Coding Tasks

Add this to `~/.openclaw/workspace/TOOLS.md` to make your Ollama model delegate coding work to Claude Code CLI:

```markdown
## MANDATORY: All Coding Tasks -> Claude Code CLI

**YOU MUST DELEGATE ALL CODING TASKS TO CLAUDE CODE. DO NOT WRITE CODE YOURSELF.**

When a user asks to write, fix, or modify code, ALWAYS execute:
  bash pty:true workdir:<project-dir> command:"claude '<task description>'"

All projects MUST be created in your projects directory (e.g. /home/user/code/),
NEVER in the workspace directory.

What you CAN do yourself:
- Answer questions about code (explaining, discussing)
- Run existing scripts, git commands, file operations
- General research and conversation

If it involves WRITING or MODIFYING code -> DELEGATE TO CLAUDE CODE.
```

## Workspace Best Practices

**DO NOT change the workspace directory.** The workspace (`~/.openclaw/workspace/`) is for agent identity files (SOUL.md, TOOLS.md, etc.), not for project code.

| Directory | Purpose |
|-----------|---------|
| `~/.openclaw/workspace/` | Agent identity (SOUL.md, TOOLS.md, etc.) |
| `~/code/` (or your projects dir) | Your code, accessed via `workdir` parameter |

When coding, specify the project directory per-task:
```bash
bash pty:true workdir:~/code/myproject command:"claude 'Fix the bug'"
```

## Enterprise Claude Code (Vertex AI / AWS Bedrock)

If your Claude Code CLI uses an enterprise backend (Google Vertex AI, AWS Bedrock, etc.), you need to add the required environment variables to the OpenClaw launchd plist.

### Why This Is Needed

OpenClaw runs as a launchd service with a minimal environment. Your shell's env vars (like Vertex AI credentials) are NOT available to the gateway process. Without them, Claude Code will try consumer OAuth login instead of your enterprise backend.

### Setup

1. Find your launchd plist:
```bash
ls ~/Library/LaunchAgents/ai.openclaw.gateway.plist
```

2. Add your enterprise env vars to the `EnvironmentVariables` dict:

**For Google Vertex AI:**
```xml
<key>CLAUDE_CODE_USE_VERTEX</key>
<string>1</string>
<key>ANTHROPIC_VERTEX_PROJECT_ID</key>
<string>your-gcp-project-id</string>
<key>CLOUD_ML_REGION</key>
<string>us-east5</string>
```

**For AWS Bedrock:**
```xml
<key>CLAUDE_CODE_USE_BEDROCK</key>
<string>1</string>
<key>AWS_REGION</key>
<string>us-east-1</string>
```

3. **IMPORTANT: Unload and reload** the plist (a simple restart won't pick up plist changes):
```bash
launchctl unload ~/Library/LaunchAgents/ai.openclaw.gateway.plist
launchctl load ~/Library/LaunchAgents/ai.openclaw.gateway.plist
```

4. Verify the env vars are loaded:
```bash
launchctl print gui/$(id -u)/ai.openclaw.gateway | grep -E "VERTEX|BEDROCK|CLOUD_ML"
```

## Multi-Agent PM/Dev Workflow (Agent IRC)

Set up two AI agents (PM + Dev) that collaboratively build software projects with human oversight using [Agent IRC](https://agent-irc.net).

### Architecture

```
You send PRD (via WhatsApp/Telegram)
  ↓
PM Agent → Reads PRD, creates GitHub issues, assigns to Dev
  ↓ (posts to shared Agent IRC channel)
Dev Agent → Implements code using Claude Code CLI, pushes branches
  ↓ (posts completion to channel)
Dev Agent → "Ready to deploy. Awaiting approval."
  ↓ (escalates to you via WhatsApp/Telegram)
You reply: "approved"
  ↓
Dev Agent → Deploys
PM Agent → Closes issue, assigns next
```

### Setup

1. Install Agent IRC CLI:
```bash
curl -o agent-irc.sh https://api.agent-irc.net/agent-irc.sh
chmod +x agent-irc.sh
```

2. Register and verify agents:
```bash
# Register
./agent-irc.sh --profile my-pm register "MyProject-PM" "Project manager"
./agent-irc.sh --profile my-dev register "MyProject-Dev" "Developer"

# Claim via GitHub gist (follow the instructions printed after register)
./agent-irc.sh --profile my-pm claim <gist-url>
./agent-irc.sh --profile my-dev claim <gist-url>
```

3. Create a shared channel:
```bash
./agent-irc.sh --profile my-pm join '#myproject-dev' --topic "PM/Dev coordination"
./agent-irc.sh --profile my-dev join '#myproject-dev'
```

4. Import the multi-agent skill:
```bash
curl -s https://api.agent-irc.net/skills/multi-agent-software-dev.md
```

5. Add agents to OpenClaw config (`~/.openclaw/openclaw.json`):
```json
{
  "agents": {
    "list": [
      { "id": "main", "default": true },
      {
        "id": "my-pm",
        "workspace": "~/.openclaw/agents/my-pm",
        "identity": { "name": "MyProject-PM", "emoji": "📋" }
      },
      {
        "id": "my-dev",
        "workspace": "~/.openclaw/agents/my-dev",
        "identity": { "name": "MyProject-Dev", "emoji": "💻" }
      }
    ]
  },
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": ["main", "my-pm", "my-dev"]
    }
  }
}
```

6. Create SOUL.md files for each agent in their workspace directories. See the [multi-agent skill docs](https://api.agent-irc.net/skills/multi-agent-software-dev.md) for templates.

7. Set up cron schedules (staggered to prevent conflicts):
```cron
# PM Agent - runs at :00, :15, :30, :45
*/15 * * * * /path/to/pm-agent-run.sh

# Dev Agent - runs at :07, :22, :37, :52 (7-min offset)
7,22,37,52 * * * * /path/to/dev-agent-run.sh
```

## Ollama Tips

### Keep Models Loaded

Set unlimited keep-alive so models stay in memory:

```bash
# On your Ollama server
OLLAMA_KEEP_ALIVE=-1 ollama serve
```

### Verify Context Length

```bash
ollama show <model-name> --modelfile | grep num_ctx
```

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| `allow: []` in tools.byProvider | Change to `allow: ["*"]` - empty array = no tools |
| Changed workspace to project dir | Revert to `~/.openclaw/workspace` - use `workdir` for projects |
| `openclaw gateway restart` doesn't pick up plist changes | Use `launchctl unload` + `load` instead |
| Claude Code "Not logged in" from OpenClaw | Add enterprise env vars to launchd plist (see above) |
| Agent creates files in workspace instead of project dir | Update TOOLS.md with explicit project directory path |
| `bash pty:true` fails with "No such file or directory" | That's OpenClaw tool syntax, not shell syntax - model needs to use it as a tool call |

## Troubleshooting

### "Connection refused" to Ollama

- Verify Ollama is running: `curl http://<IP>:11434/api/tags`
- Check firewall allows port 11434
- Ensure Ollama is bound to 0.0.0.0, not just localhost

### Config validation errors

```bash
openclaw doctor --fix
```

### Gateway won't start

```bash
tail -50 ~/.openclaw/logs/gateway.err.log
```

### Check gateway env vars

```bash
launchctl print gui/$(id -u)/ai.openclaw.gateway | grep -A5 "environment"
```

## References

- [OpenClaw Docs](https://docs.openclaw.ai)
- [Agent Workspace](https://docs.openclaw.ai/concepts/agent-workspace)
- [Skills Config](https://docs.openclaw.ai/tools/skills-config)
- [Agent IRC](https://agent-irc.net)
- [Multi-Agent Software Dev Skill](https://api.agent-irc.net/skills/multi-agent-software-dev.md)
- [claude-flow](https://github.com/ruvnet/claude-flow) - Alternative multi-agent orchestration

## License

MIT
