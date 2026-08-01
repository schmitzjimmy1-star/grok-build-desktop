# OpenRouter in GrokBuild — paste-your-key setup

OpenRouter is a first-class provider template as of 2026-07-31. One OpenRouter key
fronts models from many labs (OpenAI, Anthropic, Google, xAI, Meta, …), and because it
speaks the OpenAI Chat Completions protocol it rides GrokBuild's existing provider,
Keychain, catalog, and endpoint-trust machinery — no new runtime, no dependency.

## Get a key

<https://openrouter.ai/keys> → create a key (starts with `sk-or-...`). Add credit or a
spend limit on your OpenRouter account as you like; GrokBuild never sees your balance.

## Connect it (four clicks + paste)

1. **Settings → Models** (gear, top-right).
2. Under **Add Provider → Provider Templates**, click **Install** on the **OpenRouter**
   tile. The editor opens pre-filled: id `openrouter`, base URL
   `https://openrouter.ai/api/v1`, **Bearer token** auth.
3. Paste your key into **API key**, then click **Test connection** to fetch the live
   catalog (~300+ models).
4. Click **Add Provider**. Your key is stored in the **macOS Keychain**; only the
   CLI-required projection lands in `~/.grok/config.toml` (mode `0600`).

## Add a model

On the saved **OpenRouter** provider row, click **Add model**, then **Fetch models** and
pick one. OpenRouter model ids are **lab-prefixed** — e.g. `openai/gpt-4o`,
`anthropic/claude-3.7-sonnet`, `x-ai/grok-4`, or `openrouter/auto` (its auto-router).
The `models` dropdown supports type-to-search. Save, then select the model from the
composer's model picker like any other.

## Notes

- **Security:** the key travels only over HTTPS (OpenRouter is https-only), never over a
  cross-origin redirect (bounded same-origin redirect policy), and is redacted from
  diagnostics. It lives in the Keychain, not in UserDefaults.
- **grok owns execution:** GrokBuild configures the provider; the grok CLI actually calls
  OpenRouter when a session uses one of its models. A `Reply OK` smoke through a real
  session is the only proof a given model/route works end to end (catalog success alone
  isn't) — run one after adding your first model.
- **Not built (by design):** the one-click "Connect with OpenRouter" OAuth/PKCE flow is a
  future nicety; the paste-key path above is the supported route and needs no OAuth. A
  searchable (vs type-to-search dropdown) model picker is also a future nicety given
  OpenRouter's large catalog.

## Why not Goose?

Goose was considered and **intentionally skipped as redundant**: GrokBuild is a native
shell over the grok CLI, and grok already consumes OpenAI-compatible providers directly
(that is exactly how the existing `gpt-5.6-terra` and `kimi-k3` custom models work). So
OpenRouter flows straight through grok — adding Goose would mean wiring a second agent
runtime into the app for zero incremental capability toward "use my OpenRouter key."
