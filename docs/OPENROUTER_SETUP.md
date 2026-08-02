# OpenRouter in GrokBuild — OAuth or API key

OpenRouter is a first-class provider template. One OpenRouter key
fronts models from many labs (OpenAI, Anthropic, Google, xAI, Meta, …), and because it
speaks the OpenAI Chat Completions protocol it rides GrokBuild's existing provider,
Keychain, catalog, and endpoint-trust machinery — no new runtime, no dependency.

## Recommended: connect in your browser

1. Open **Settings → Models**.
2. Under **Add Provider → Provider Templates**, install **OpenRouter**.
3. Click **Connect with OpenRouter…**. GrokBuild opens OpenRouter's documented S256
   browser flow and listens only on `127.0.0.1`, on an ephemeral port and random exact
   callback path.
4. Approve the connection in OpenRouter. The returned user-controlled API key is saved
   to macOS Keychain with device-only accessibility; the authorization code and PKCE
   verifier are discarded.
5. Click **Test connection** to validate the credential and fetch the live model catalog.

Cancel, timeout, wrong-path, malformed, and exchange-failure paths leave the previous
credential untouched. **Disconnect locally** removes the Keychain item and owner-only CLI
projection, but does not claim to revoke the remote key. Use **Manage or revoke remote
keys** for that separate OpenRouter account action.

## Alternative: paste an API key

Create a key at <https://openrouter.ai/keys>. Add credit or a spend limit on your
OpenRouter account as you like; GrokBuild never sees your balance.

1. **Settings → Models** (gear, top-right).
2. Under **Add Provider → Provider Templates**, click **Install** on the **OpenRouter**
   tile. The editor opens pre-filled: id `openrouter`, base URL
   `https://openrouter.ai/api/v1`, **Bearer token** auth.
3. Paste your key into **API key**, then click **Test connection** to fetch the live
   catalog.
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
  diagnostics. UserDefaults contains only non-secret connection provenance; the key lives
  in Keychain, not UserDefaults.
- **grok owns execution:** GrokBuild configures the provider; the grok CLI actually calls
  OpenRouter when a session uses one of its models. A `Reply OK` smoke through a real
  session is the only proof a given model/route works end to end (catalog success alone
  isn't) — run one after adding your first model.
- **No silent sends:** connection and catalog validation are separate from model inference.
  GrokBuild never sends a prompt merely because a provider was connected or tested.

## Why not Goose?

Goose was considered and **intentionally skipped as redundant**: GrokBuild is a native
shell over the grok CLI, and grok already consumes OpenAI-compatible providers directly
(that is exactly how the existing `gpt-5.6-terra` and `kimi-k3` custom models work). So
OpenRouter flows straight through grok — adding Goose would mean wiring a second agent
runtime into the app for zero incremental capability toward "use my OpenRouter key."
