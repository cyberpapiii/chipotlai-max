# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Chipotlai Max** is a meme fork of [OpenCode](https://github.com/anomalyco/opencode) (MIT, 120k+ stars) that ships Chipotle's "Pepper AI" support bot as the default model via the [chipotle-llm-provider](https://github.com/Gonzih/chipotle-llm-provider) proxy. The full project brief is in `**Chipotlai Max Project Brief**.md`.

## Key Upstream Repos

- **OpenCode** (base): `https://github.com/anomalyco/opencode` — provider-agnostic AI coding agent (CLI + desktop + VS Code extension). Build system: Bun + Turborepo + Nix.
- **Chipotle LLM Provider** (proxy): `https://github.com/Gonzih/chipotle-llm-provider` — OpenAI-compatible proxy at `localhost:3000/v1`, model name `pepper-1`, any API key works. Added as git submodule at `chipotle-llm-provider/`.

## Build & Run

Once the fork is set up:
```bash
bun install && bun run build    # inherited from OpenCode
cd chipotle-llm-provider && npm install && npm run dev  # start the proxy
```

## Architecture Notes

- Provider/model config lives in `packages/` — look for `ProviderID`/`ModelID` types. The default provider should be hardcoded as:
  - ID: `chipotle-pepper`, model: `pepper-1`, baseUrl: `http://localhost:3000/v1`, apiKey: any string
- UI theme (Tailwind/CSS vars) also in `packages/` or `sdks/vscode/`
- Chipotle brand palette: primary `#AC2318`, dark `#441500`, accent `#B68207`, background `#FFFFFF`, text `#451400`

## Current State

The repo currently contains only the project brief. Implementation has not started. The brief outlines 6 steps: fork & setup, hardcode Pepper provider, rename to Chipotlai Max, Chipotle branding, bundle the proxy, meme polish.
