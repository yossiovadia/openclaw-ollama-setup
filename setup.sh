#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
TOOLS_MD="$HOME/.openclaw/workspace/TOOLS.md"

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     OpenClaw + Ollama + Claude Code Setup                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"

    if [ ! -f "$OPENCLAW_CONFIG" ]; then
        echo -e "${RED}Error: OpenClaw config not found at $OPENCLAW_CONFIG${NC}"
        echo "Please install OpenClaw first: https://openclaw.ai"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} OpenClaw config found"

    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is required but not installed${NC}"
        echo "Install with: brew install jq"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} jq installed"

    if command -v claude &> /dev/null; then
        CLAUDE_AVAILABLE=true
        echo -e "${GREEN}✓${NC} Claude Code CLI available"
    else
        CLAUDE_AVAILABLE=false
        echo -e "${YELLOW}!${NC} Claude Code CLI not found (optional)"
    fi
}

# Detect or ask for Ollama endpoint
get_ollama_endpoint() {
    echo ""
    echo -e "${YELLOW}Configuring Ollama endpoint...${NC}"

    # Try localhost first
    if curl -s --connect-timeout 2 http://127.0.0.1:11434/api/tags &> /dev/null; then
        echo -e "${GREEN}✓${NC} Found Ollama running locally (127.0.0.1:11434)"
        read -p "Use local Ollama? [Y/n]: " use_local
        if [[ ! "$use_local" =~ ^[Nn] ]]; then
            OLLAMA_HOST="127.0.0.1"
            OLLAMA_PORT="11434"
            return
        fi
    fi

    # Ask for remote endpoint
    echo ""
    read -p "Enter Ollama IP address: " OLLAMA_HOST
    read -p "Enter Ollama port [11434]: " OLLAMA_PORT
    OLLAMA_PORT=${OLLAMA_PORT:-11434}

    # Test connection
    echo -e "${YELLOW}Testing connection to $OLLAMA_HOST:$OLLAMA_PORT...${NC}"
    if ! curl -s --connect-timeout 5 "http://$OLLAMA_HOST:$OLLAMA_PORT/api/tags" &> /dev/null; then
        echo -e "${RED}Error: Cannot connect to Ollama at $OLLAMA_HOST:$OLLAMA_PORT${NC}"
        echo "Please verify Ollama is running and accessible."
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Connected to Ollama"
}

# List and select model
select_model() {
    echo ""
    echo -e "${YELLOW}Fetching available models...${NC}"

    MODELS_JSON=$(curl -s "http://$OLLAMA_HOST:$OLLAMA_PORT/api/tags")

    # Parse model names
    MODELS=($(echo "$MODELS_JSON" | jq -r '.models[].name'))

    if [ ${#MODELS[@]} -eq 0 ]; then
        echo -e "${RED}No models found on Ollama server${NC}"
        exit 1
    fi

    echo ""
    echo "Available models:"
    for i in "${!MODELS[@]}"; do
        echo "  $((i+1)). ${MODELS[$i]}"
    done

    echo ""
    read -p "Select model number [1]: " model_choice
    model_choice=${model_choice:-1}

    MODEL_NAME="${MODELS[$((model_choice-1))]}"

    if [ -z "$MODEL_NAME" ]; then
        echo -e "${RED}Invalid selection${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓${NC} Selected: $MODEL_NAME"

    # Get model details for context window
    echo -e "${YELLOW}Fetching model details...${NC}"
    MODEL_INFO=$(curl -s "http://$OLLAMA_HOST:$OLLAMA_PORT/api/show" -d "{\"name\": \"$MODEL_NAME\"}" 2>/dev/null || echo "{}")

    # Try to extract num_ctx, default to 128000
    CONTEXT_WINDOW=$(echo "$MODEL_INFO" | jq -r '.parameters // "" | capture("num_ctx\\s+(?<ctx>[0-9]+)") | .ctx // empty' 2>/dev/null || echo "")

    if [ -z "$CONTEXT_WINDOW" ]; then
        read -p "Enter context window size [128000]: " CONTEXT_WINDOW
        CONTEXT_WINDOW=${CONTEXT_WINDOW:-128000}
    else
        echo -e "${GREEN}✓${NC} Detected context window: $CONTEXT_WINDOW"
    fi
}

# Configure max tokens
configure_tokens() {
    echo ""
    read -p "Enter max output tokens [16384]: " MAX_TOKENS
    MAX_TOKENS=${MAX_TOKENS:-16384}
}

# Configure workspace directory
configure_workspace() {
    echo ""
    echo -e "${YELLOW}Configuring workspace directory...${NC}"
    echo "This is where coding agents will work. Set it to your projects folder."
    read -p "Enter workspace directory [$HOME/code]: " WORKSPACE_DIR
    WORKSPACE_DIR=${WORKSPACE_DIR:-"$HOME/code"}

    # Expand ~ if present
    WORKSPACE_DIR="${WORKSPACE_DIR/#\~/$HOME}"

    if [ ! -d "$WORKSPACE_DIR" ]; then
        read -p "Directory doesn't exist. Create it? [Y/n]: " create_dir
        if [[ ! "$create_dir" =~ ^[Nn] ]]; then
            mkdir -p "$WORKSPACE_DIR"
            echo -e "${GREEN}✓${NC} Created $WORKSPACE_DIR"
        fi
    fi
}

# Backup and update config
update_openclaw_config() {
    echo ""
    echo -e "${YELLOW}Updating OpenClaw configuration...${NC}"

    # Backup
    cp "$OPENCLAW_CONFIG" "$OPENCLAW_CONFIG.bak"
    echo -e "${GREEN}✓${NC} Backup created: $OPENCLAW_CONFIG.bak"

    # Create the new provider config
    PROVIDER_JSON=$(cat <<EOF
{
  "baseUrl": "http://$OLLAMA_HOST:$OLLAMA_PORT/v1",
  "apiKey": "ollama",
  "models": [
    {
      "id": "$MODEL_NAME",
      "name": "$MODEL_NAME (Ollama)",
      "api": "openai-completions",
      "reasoning": false,
      "input": ["text"],
      "cost": {
        "input": 0,
        "output": 0,
        "cacheRead": 0,
        "cacheWrite": 0
      },
      "contextWindow": $CONTEXT_WINDOW,
      "maxTokens": $MAX_TOKENS
    }
  ]
}
EOF
)

    # Update config using jq
    jq --argjson provider "$PROVIDER_JSON" \
       --arg model "ollama/$MODEL_NAME" \
       --arg workspace "$WORKSPACE_DIR" \
       '
       .models.providers.ollama = $provider |
       .agents.defaults.workspace = $workspace |
       .agents.defaults.model.primary = $model |
       .tools.byProvider[$model] = {"allow": ["*"]}
       ' "$OPENCLAW_CONFIG" > "$OPENCLAW_CONFIG.tmp" && mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG"

    echo -e "${GREEN}✓${NC} OpenClaw config updated"
}

# Add Claude Code routing
setup_claude_routing() {
    if [ "$CLAUDE_AVAILABLE" != "true" ]; then
        return
    fi

    echo ""
    read -p "Route coding tasks to Claude Code CLI? [Y/n]: " setup_claude
    if [[ "$setup_claude" =~ ^[Nn] ]]; then
        return
    fi

    read -p "Default project directory [~/code]: " PROJECT_DIR
    PROJECT_DIR=${PROJECT_DIR:-"~/code"}

    # Check if already configured
    if grep -q "MANDATORY.*Coding Tasks" "$TOOLS_MD" 2>/dev/null; then
        echo -e "${YELLOW}!${NC} Claude Code routing already configured in TOOLS.md"
        return
    fi

    # Append to TOOLS.md
    cat >> "$TOOLS_MD" <<EOF

---

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

If no project directory is specified, use \`$PROJECT_DIR\` or ask the user.

### What You CAN Do Yourself

- Answer questions about code (explaining, discussing)
- Run existing scripts, git commands, file operations
- General research and conversation

**But if it involves WRITING or MODIFYING code → DELEGATE TO CLAUDE CODE.**
EOF

    echo -e "${GREEN}✓${NC} Claude Code routing added to TOOLS.md"
}

# Restart gateway
restart_gateway() {
    echo ""
    read -p "Restart OpenClaw gateway now? [Y/n]: " restart
    if [[ ! "$restart" =~ ^[Nn] ]]; then
        echo -e "${YELLOW}Restarting gateway...${NC}"
        openclaw gateway restart 2>&1 | tail -1
        sleep 2
        echo -e "${GREEN}✓${NC} Gateway restarted"
    fi
}

# Summary
print_summary() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Setup complete!${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Configuration:"
    echo "  Ollama endpoint: http://$OLLAMA_HOST:$OLLAMA_PORT"
    echo "  Model: ollama/$MODEL_NAME"
    echo "  Context window: $CONTEXT_WINDOW"
    echo "  Max tokens: $MAX_TOKENS"
    echo "  Workspace: $WORKSPACE_DIR"
    if [ "$CLAUDE_AVAILABLE" = "true" ]; then
        echo "  Claude Code: Enabled for coding tasks"
    fi
    echo ""
    echo "Files modified:"
    echo "  $OPENCLAW_CONFIG"
    if [ "$CLAUDE_AVAILABLE" = "true" ]; then
        echo "  $TOOLS_MD"
    fi
    echo ""
}

# Main
main() {
    check_prerequisites
    get_ollama_endpoint
    select_model
    configure_tokens
    configure_workspace
    update_openclaw_config
    setup_claude_routing
    restart_gateway
    print_summary
}

main
