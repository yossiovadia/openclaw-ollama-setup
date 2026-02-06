# OpenClaw + Ollama + Claude Code Setup

Configure OpenClaw to use a remote Ollama instance as the primary model, with automatic delegation of coding tasks to Claude Code CLI.

**Author:** Yossi Ovadia ([@yossiovadia](https://github.com/yossiovadia))

## Prerequisites

- [OpenClaw](https://openclaw.ai) installed and running
- [Ollama](https://ollama.com) running (local or remote)
- [Claude Code CLI](https://docs.anthropic.com/claude-code) installed (for coding delegation)

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

In the same file, set the primary model under `agents.defaults.model`:

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

Under `tools.byProvider`, add:

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

If you have Claude Code CLI installed and want coding tasks delegated to it, add this to `~/.openclaw/workspace/TOOLS.md`:

```markdown
## ⚠️ MANDATORY: All Coding Tasks → Claude Code CLI

**YOU MUST DELEGATE ALL CODING TASKS TO CLAUDE CODE. DO NOT WRITE CODE YOURSELF.**

This is a strict requirement. When a user asks you to:
- Write, create, or generate code
- Fix bugs or debug issues
- Refactor or modify existing code
- Build features or applications
- Review code or PRs
- Create scripts, programs, or any programming work

**ALWAYS execute this command:**

\`\`\`bash
bash pty:true workdir:<project-dir> command:"claude '<detailed task description>'"
\`\`\`

### Why This Rule Exists

Claude Code CLI is a specialized coding agent with superior code generation capabilities.
You are the orchestrator - your job is to delegate coding work, not do it yourself.

### Default Directory

If no project directory is specified, use `~/code` or ask the user.

### What You CAN Do Yourself

- Answer questions about code (explaining, discussing)
- Run existing scripts, git commands, file operations
- General research and conversation

**But if it involves WRITING or MODIFYING code → DELEGATE TO CLAUDE CODE.**
```

## Ollama Tips

### Keep Models Loaded

Set unlimited keep-alive so models stay in memory:

```bash
# On your Ollama server
OLLAMA_KEEP_ALIVE=-1 ollama serve
```

### Verify Context Length

Check your model's context window:

```bash
ollama show <model-name> --modelfile | grep num_ctx
```

## Troubleshooting

### "Connection refused" to Ollama

- Verify Ollama is running: `curl http://<IP>:11434/api/tags`
- Check firewall allows port 11434
- Ensure Ollama is bound to 0.0.0.0, not just localhost

### Config validation errors

Run the doctor:

```bash
openclaw doctor --fix
```

### Gateway won't start

Check logs:

```bash
tail -50 ~/.openclaw/logs/gateway.err.log
```

## License

MIT
