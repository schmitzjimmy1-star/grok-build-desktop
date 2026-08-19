from __future__ import annotations

import hashlib
import json
import os
import tempfile
import threading
import unittest
import urllib.request
from pathlib import Path

from scripts.acceptance.harness.candidate_process_driver import (
    CAMPAIGN_ID,
    LIVE_SERIALIZER_PAYLOAD_CEILING,
    MODEL_ID,
    OFFICIAL_CLI,
    OFFICIAL_CLI_SHA256,
    PROVIDER_FACING_MODEL,
    STAGED_PAGER_SHA256,
    config_projection_bytes,
    conservative_request_bound_tokens,
    exact_loopback_endpoint_sha256,
    one_allocation,
    require_official_cli_untouched,
    require_staged_selection,
    sha256_bytes,
    write_isolated_home,
    write_v3_manifest,
)
from scripts.acceptance.harness.errors import HarnessError
from scripts.acceptance.harness.loopback_provider import (
    CHAT_OK,
    LoopbackCluster,
    completion_to_sse,
)


ROOT = Path(__file__).resolve().parents[1]
SELECTION_ENV = os.environ.get("GROKBUILD_SLICE4B3_RUNTIME_SELECTION") or ""
SELECTION = Path(SELECTION_ENV) if SELECTION_ENV else None
PROMPT = "Reply with exactly the word pong."


class Slice4B5LoopbackAndDriverContracts(unittest.TestCase):
    def test_chat_completions_speaks_sse_not_a_json_object(self) -> None:
        rendered = completion_to_sse(CHAT_OK).decode()
        self.assertIn('"object":"chat.completion.chunk"', rendered)
        self.assertIn('"content":"pong"', rendered)
        self.assertIn('"simulated":true', rendered)
        self.assertIn("data: [DONE]", rendered)
        self.assertNotIn('"object":"chat.completion"', rendered)

        ordered = completion_to_sse(
            {
                "id": "s4b5-read-1",
                "object": "chat.completion",
                "created": 0,
                "model": "loopback-model",
                "choices": [
                    {
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": None,
                            "tool_calls": [
                                {
                                    "id": "call_read_1",
                                    "type": "function",
                                    "function": {
                                        "name": "read_file",
                                        "arguments": '{"target_file":"ONE.txt"}',
                                    },
                                }
                            ],
                        },
                        "finish_reason": "tool_calls",
                    }
                ],
                "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2, "simulated": True},
            }
        ).decode()
        self.assertIn('"name":"read_file"', ordered)
        self.assertIn("target_file", ordered)
        self.assertNotIn("GrokBuild:read_file", ordered)

        missing = completion_to_sse(
            {
                "id": "s4b5-chat-missing-usage",
                "object": "chat.completion",
                "created": 0,
                "model": "loopback-model",
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": "pong"},
                        "finish_reason": "stop",
                    }
                ],
            }
        ).decode()
        self.assertIn('"content":"pong"', missing)
        self.assertNotIn('"usage"', missing)

        cluster = LoopbackCluster(mode="normal")
        identity = cluster.start()
        try:
            payload = json.dumps(
                {
                    "model": "loopback-model",
                    "stream": True,
                    "stream_options": {"include_usage": True},
                    "messages": [{"role": "user", "content": PROMPT}],
                }
            ).encode()
            request = urllib.request.Request(
                identity["baseUrl"] + "/chat/completions",
                data=payload,
                headers={
                    "Accept": "text/event-stream",
                    "Content-Type": "application/json",
                    "Authorization": "Bearer S4B5-contract-END",
                },
                method="POST",
            )
            with urllib.request.urlopen(request, timeout=5) as response:
                self.assertEqual(response.status, 200)
                self.assertIn("text/event-stream", response.headers.get("Content-Type", ""))
                body = response.read().decode()
            self.assertIn("data: ", body)
            self.assertIn('"content":"pong"', body)
            self.assertIn("data: [DONE]", body)
            self.assertNotIn('"object":"chat.completion"', body)
            snapshot = cluster.snapshot()
            self.assertEqual(snapshot["primary"]["connections"], 1)
            self.assertEqual(snapshot["redirect"]["connections"], 0)
            self.assertEqual(snapshot["retry"]["connections"], 0)
        finally:
            cluster.close()

    def test_loopback_binds_only_127_and_labels_usage_simulated(self) -> None:
        cluster = LoopbackCluster(mode="normal")
        identity = cluster.start()
        try:
            self.assertTrue(identity["baseUrl"].startswith("http://127.0.0.1:"))
            self.assertTrue(identity["simulated"])
            snapshot = cluster.snapshot()
            self.assertEqual(snapshot["primary"]["connections"], 0)
            self.assertEqual(snapshot["redirect"]["connections"], 0)
            self.assertEqual(snapshot["retry"]["connections"], 0)
        finally:
            cluster.close()

    def test_endpoint_sha_matches_cli_plain_join(self) -> None:
        base = "http://127.0.0.1:9/v1"
        expected = hashlib.sha256(b"http://127.0.0.1:9/v1/chat/completions").hexdigest()
        self.assertEqual(exact_loopback_endpoint_sha256(base, "chat_completions"), expected)

    def test_remote_host_is_refused(self) -> None:
        with self.assertRaisesRegex(HarnessError, "non-loopback"):
            exact_loopback_endpoint_sha256("https://openrouter.ai/api/v1", "chat_completions")

    def test_official_and_staged_pins_are_distinct_constants(self) -> None:
        self.assertEqual(
            OFFICIAL_CLI_SHA256,
            "39366f7756a090b735cc1df8c93a8c0c3c7871555cf6cbb28f9351ca82936485",
        )
        self.assertEqual(
            STAGED_PAGER_SHA256,
            "f434fa4f17160c8771d3b57bfc62499e252413c4d1fc5ab22bee1a18f2bc933b",
        )
        self.assertNotEqual(OFFICIAL_CLI_SHA256, STAGED_PAGER_SHA256)

    def test_official_cli_digest_is_the_untouched_1_0_4_binary(self) -> None:
        if not OFFICIAL_CLI.is_file():
            self.skipTest("official ~/.grok/bin/grok is owner-local and is not on CI runners")
        digest = require_official_cli_untouched()
        self.assertEqual(digest, OFFICIAL_CLI_SHA256)
        self.assertEqual(digest, require_official_cli_untouched(digest))

    def test_driver_refuses_to_treat_official_cli_as_the_staged_pager(self) -> None:
        if not OFFICIAL_CLI.is_file():
            self.skipTest("official ~/.grok/bin/grok is owner-local and is not on CI runners")
        self.assertNotEqual(sha256_bytes(OFFICIAL_CLI.read_bytes()), STAGED_PAGER_SHA256)

    def test_config_projection_omits_the_placeholder_key(self) -> None:
        projection = config_projection_bytes("http://127.0.0.1:9/v1")
        text = projection.decode()
        self.assertIn(MODEL_ID, text)
        self.assertIn(PROVIDER_FACING_MODEL, text)
        self.assertNotIn("api_key", text)
        self.assertNotIn("loopback-placeholder-not-live", text)
        self.assertNotIn("sk-", text.lower())

    def test_isolated_home_and_manifest_cover_live_serializer_ceiling(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            home = Path(raw) / "home"
            home.mkdir()
            os.chmod(home, 0o700)
            base = "http://127.0.0.1:9/v1"
            write_isolated_home(home, base)
            bound = conservative_request_bound_tokens()
            self.assertEqual(bound, LIVE_SERIALIZER_PAYLOAD_CEILING + 256)
            ceiling = 100_000
            alloc = one_allocation(
                base,
                allocation_id="s4b5-normal",
                packet_id="S4B5-NORMAL",
                prompt=PROMPT,
                token_ceiling=ceiling,
                max_model_calls=1,
            )
            manifest = write_v3_manifest(Path(raw) / "authority", base, [alloc])
            document = json.loads(manifest.read_text())
            self.assertEqual(document["schemaVersion"], 3)
            self.assertEqual(document["campaignId"], CAMPAIGN_ID)
            self.assertEqual(document["campaignPolicy"]["absoluteTokenCeiling"], 20_000_000)
            self.assertEqual(document["campaignPolicy"]["allocatableTokenCeiling"], 19_000_000)
            self.assertEqual(document["campaignPolicy"]["unreachableReserveTokens"], 1_000_000)
            self.assertEqual(document["allocations"][0]["routeExpectation"]["maxFinalSerializedPayloadBytes"], 65_536)
            self.assertGreaterEqual(ceiling, bound)
            self.assertEqual((Path(raw) / "authority" / "ledger.json").stat().st_size, 0)
            toml = (home / ".grok" / "config.toml").read_text()
            self.assertIn(base, toml)
            self.assertNotIn("openrouter.ai", toml)
            self.assertNotIn("api_key", toml)
            self.assertNotIn("loopback-placeholder-not-live", toml)

    def test_undersized_golden_envelope_is_refused(self) -> None:
        with self.assertRaisesRegex(HarnessError, "live serializer ceiling"):
            one_allocation(
                "http://127.0.0.1:9/v1",
                allocation_id="too-small",
                packet_id="TOO-SMALL",
                prompt=PROMPT,
                token_ceiling=20_000,
                max_model_calls=1,
            )

    def test_redirect_and_retry_listeners_stay_at_zero_without_a_client(self) -> None:
        cluster = LoopbackCluster(mode="redirect")
        cluster.start()
        try:
            snapshot = cluster.snapshot()
            self.assertEqual(snapshot["redirect"]["connections"], 0)
            self.assertEqual(snapshot["retry"]["connections"], 0)
        finally:
            cluster.close()

    def test_hold_and_stream_fail_modes_start_without_connections(self) -> None:
        for mode in ("hold", "stream_fail", "missing_usage", "hold_after_body"):
            cluster = LoopbackCluster(mode=mode)
            cluster.start()
            try:
                self.assertEqual(cluster.snapshot()["primary"]["connections"], 0)
            finally:
                cluster.close()

    def test_hold_after_body_streams_pong_without_done(self) -> None:
        cluster = LoopbackCluster(mode="hold_after_body")
        identity = cluster.start()
        try:
            payload = json.dumps(
                {
                    "model": "loopback-model",
                    "stream": True,
                    "messages": [{"role": "user", "content": PROMPT}],
                }
            ).encode()
            request = urllib.request.Request(
                identity["baseUrl"] + "/chat/completions",
                data=payload,
                headers={
                    "Accept": "text/event-stream",
                    "Content-Type": "application/json",
                    "Authorization": "Bearer S4B5-contract-END",
                },
                method="POST",
            )
            collected = bytearray()
            finished = threading.Event()

            def _read() -> None:
                try:
                    with urllib.request.urlopen(request, timeout=5) as response:
                        while True:
                            chunk = response.read(64)
                            if not chunk:
                                break
                            collected.extend(chunk)
                            if b'"content":"pong"' in collected:
                                break
                except Exception:
                    pass
                finally:
                    finished.set()

            thread = threading.Thread(target=_read, daemon=True)
            thread.start()
            self.assertTrue(finished.wait(timeout=5) or b'"content":"pong"' in collected)
            self.assertIn(b'"content":"pong"', collected)
            self.assertNotIn(b"data: [DONE]", collected)
            self.assertEqual(cluster.snapshot()["redirect"]["connections"], 0)
            self.assertEqual(cluster.snapshot()["retry"]["connections"], 0)
        finally:
            cluster.close()

    def test_stream_fail_closes_after_truncated_chunk(self) -> None:
        cluster = LoopbackCluster(mode="stream_fail")
        identity = cluster.start()
        try:
            payload = json.dumps(
                {
                    "model": "loopback-model",
                    "stream": True,
                    "messages": [{"role": "user", "content": PROMPT}],
                }
            ).encode()
            request = urllib.request.Request(
                identity["baseUrl"] + "/chat/completions",
                data=payload,
                headers={
                    "Accept": "text/event-stream",
                    "Content-Type": "application/json",
                },
                method="POST",
            )
            try:
                with urllib.request.urlopen(request, timeout=5) as response:
                    body = response.read()
            except Exception:
                return
            self.assertNotIn(b"data: [DONE]", body)
            self.assertIn(b"po", body)
        finally:
            cluster.close()

    def test_staged_selection_is_the_signed_pager_when_env_is_set(self) -> None:
        if not SELECTION_ENV:
            self.skipTest("GROKBUILD_SLICE4B3_RUNTIME_SELECTION is unset")
        if os.environ.get("CI") or os.environ.get("GITHUB_ACTIONS") == "true":
            self.skipTest("signed pager E2E is owner-local")
        selected = require_staged_selection(Path(SELECTION_ENV))
        self.assertEqual(selected["binarySHA256"], STAGED_PAGER_SHA256)
        self.assertNotEqual(Path(selected["candidatePath"]).resolve(), OFFICIAL_CLI.resolve())
