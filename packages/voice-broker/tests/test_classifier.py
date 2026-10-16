"""Offline provider contracts. Run with voice_broker on PYTHONPATH."""

import asyncio
import json
import unittest
from unittest.mock import AsyncMock

from voice_broker.classifier import (
    JevRouter,
    OpenAICompatibleRouter,
    OpenAIDecisionsRouter,
    httpx_transport,
    request_state,
)
from voice_broker.routing import RouteRequest


def request(text="Увімкни світло", context=()):
    return RouteRequest(text=text, context=context, area="kitchen", device="synthetic-pe", conversation_id="private-id")


def decision(route="ha", confidence=0.96):
    return {"answers": [{"name": "route", "type": "choice", "choice": route, "confidence": confidence}]}


class ClassifierTests(unittest.IsolatedAsyncioTestCase):
    async def test_decisions_official_contract(self):
        transport = AsyncMock(return_value=decision())
        router = OpenAIDecisionsRouter(transport)
        result = await router.route(request(context=(("user", "Dim kitchen lights"),)))
        self.assertEqual(result.route, "ha")
        self.assertGreaterEqual(result.elapsed_ms, 0)
        path, body = transport.call_args.args
        self.assertEqual(path, "/decisions")
        self.assertEqual(body["model"], "gpt-6-luna")
        self.assertEqual(body["questions"][0]["name"], "route")
        self.assertEqual({c["value"] for c in body["questions"][0]["choices"]}, {"ha", "openclaw", "clarify"})
        self.assertNotIn("private-id", body["input"])
        self.assertEqual(json.loads(body["input"])["context"][0]["role"], "user")

    async def test_jev_official_contract(self):
        transport = AsyncMock(
            return_value={"answers": {"route": {"type": "choice", "choice": "ha", "confidence": 0.9}}}
        )
        result = await JevRouter(transport).classify(request())
        self.assertEqual((result.route, result.confidence), ("ha", 0.9))
        path, body = transport.call_args.args
        self.assertEqual(path, "/systemone")
        self.assertEqual(body["model"], "jev-latest")
        self.assertEqual(set(body["questions"]["route"]["criteria"]), {"ha", "openclaw", "clarify"})

    async def test_chat_schema_and_plain_json(self):
        for strict in (True, False):
            transport = AsyncMock(
                return_value={"choices": [{"finish_reason": "stop", "message": {"content": '{"route":"openclaw"}'}}]}
            )
            result = await OpenAICompatibleRouter(transport, model="explicit-test", structured_output=strict).route(
                request()
            )
            self.assertEqual(result.route, "openclaw")
            path, body = transport.call_args.args
            self.assertEqual(path, "/chat/completions")
            self.assertEqual("response_format" in body, strict)

    async def test_responses_official_raw_output(self):
        transport = AsyncMock(
            return_value={
                "status": "completed",
                "output": [
                    {
                        "type": "message",
                        "role": "assistant",
                        "status": "completed",
                        "content": [{"type": "output_text", "text": '{"route":"ha"}'}],
                    }
                ],
            }
        )
        result = await OpenAICompatibleRouter(transport, model="test", api="responses").route(request())
        self.assertEqual(result.route, "ha")
        self.assertFalse(transport.call_args.args[1]["store"])

    async def test_malformed_refusal_and_missing_are_non_actuating(self):
        cases = [
            {},
            {"answers": []},
            {"answers": [{"name": "route", "type": "refusal"}]},
            decision("execute"),
            decision("ha", float("nan")),
            decision("ha", True),
            decision("ha", 2),
            {"answers": decision()["answers"] * 2},
        ]
        for body in cases:
            with self.subTest(body=body):
                answer = await OpenAIDecisionsRouter(AsyncMock(return_value=body)).classify(request())
                self.assertEqual(answer.route, "clarify")
                self.assertIsNotNone(answer.error)

    async def test_threshold(self):
        for confidence in (0.2, None):
            result = await OpenAIDecisionsRouter(
                AsyncMock(return_value=decision(confidence=confidence)), min_confidence=0.8
            ).classify(request())
            self.assertEqual((result.route, result.error), ("clarify", "low_confidence"))

    async def test_timeout_and_cancellation(self):
        async def stalled(*args):
            await asyncio.sleep(10)

        router = OpenAIDecisionsRouter(stalled, timeout_s=0.005)
        result = await router.classify(request())
        self.assertEqual((result.route, result.error), ("clarify", "TimeoutError"))
        task = asyncio.create_task(router.route(request()))
        await asyncio.sleep(0)
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task

    async def test_errors_redacted_and_not_retried(self):
        transport = AsyncMock(side_effect=RuntimeError("secret-token private utterance"))
        result = await OpenAIDecisionsRouter(transport).classify(request())
        self.assertEqual(result.error, "RuntimeError")
        self.assertNotIn("secret", repr(result))
        self.assertEqual(transport.await_count, 1)

    async def test_incomplete_chat_and_extra_keys(self):
        for reason, content in [("length", '{"route":"ha"}'), ("stop", '{"route":"ha","action":"on"}'), ("stop", "ha")]:
            t = AsyncMock(return_value={"choices": [{"finish_reason": reason, "message": {"content": content}}]})
            self.assertEqual((await OpenAICompatibleRouter(t, model="test").route(request())).route, "clarify")

    async def test_responses_refusal_and_incomplete(self):
        for body in [
            {"status": "incomplete"},
            {
                "status": "completed",
                "output": [
                    {"type": "message", "role": "assistant", "status": "completed", "content": [{"type": "refusal"}]}
                ],
            },
        ]:
            self.assertEqual(
                (
                    await OpenAICompatibleRouter(AsyncMock(return_value=body), model="test", api="responses").route(
                        request()
                    )
                ).route,
                "clarify",
            )

    async def test_route_injection_rejected(self):
        for content, extras in [
            ('{"route":"clarify","route":"ha"}', {}),
            ('{"route":"ha"}', {"tool_calls": [{"function": {"name": "turn_on"}}]}),
            ('{"route":"ha"}', {"function_call": {"name": "turn_on"}}),
            ('{"route":["ha"]}', {}),
            ('{"route":"ha; turn_on"}', {}),
        ]:
            transport = AsyncMock(
                return_value={"choices": [{"finish_reason": "stop", "message": {"content": content, **extras}}]}
            )
            answer = await OpenAICompatibleRouter(transport, model="test").classify(request())
            self.assertEqual(answer.route, "clarify")
            self.assertIsNotNone(answer.error)
        transport = AsyncMock(
            return_value={
                "status": "completed",
                "output": [
                    {"type": "function_call", "name": "turn_on"},
                    {
                        "type": "message",
                        "role": "assistant",
                        "status": "completed",
                        "content": [{"type": "output_text", "text": '{"route":"ha"}'}],
                    },
                ],
            }
        )
        answer = await OpenAICompatibleRouter(transport, model="test", api="responses").classify(request())
        self.assertEqual(answer.route, "clarify")
        self.assertIsNotNone(answer.error)

    async def test_nested_content_and_message_state_rejected(self):
        for extra in [{"type": "function_call"}, {"type": "unknown"}, {"type": "refusal"}]:
            t = AsyncMock(
                return_value={
                    "status": "completed",
                    "output": [
                        {
                            "type": "message",
                            "role": "assistant",
                            "status": "completed",
                            "content": [{"type": "output_text", "text": '{"route":"ha"}'}, extra],
                        }
                    ],
                }
            )
            a = await OpenAICompatibleRouter(t, model="test", api="responses").classify(request())
            self.assertEqual(a.route, "clarify")
            self.assertIsNotNone(a.error)
        for role, status in [("user", "completed"), ("assistant", "incomplete"), (None, None)]:
            t = AsyncMock(
                return_value={
                    "status": "completed",
                    "output": [
                        {
                            "type": "message",
                            "role": role,
                            "status": status,
                            "content": [{"type": "output_text", "text": '{"route":"ha"}'}],
                        }
                    ],
                }
            )
            a = await OpenAICompatibleRouter(t, model="test", api="responses").classify(request())
            self.assertEqual(a.route, "clarify")
            self.assertIsNotNone(a.error)

    async def test_duplicate_envelope_rejected(self):
        class Response:
            text = '{"answers":[],"answers":[{"type":"choice","name":"route","choice":"ha"}]}'

            def raise_for_status(self):
                pass

        client = type("Client", (), {"post": AsyncMock(return_value=Response())})()
        answer = await OpenAIDecisionsRouter(httpx_transport(client, "https://api.openai.com/v1")).classify(request())
        self.assertEqual(answer.route, "clarify")
        self.assertIsNotNone(answer.error)

    async def test_pool_transport_and_no_redirects(self):
        class Response:
            def raise_for_status(self):
                pass

            text = json.dumps(decision())

        client = type("Client", (), {"post": AsyncMock(return_value=Response())})()
        result = await OpenAIDecisionsRouter(httpx_transport(client, "https://api.openai.com/v1", "dummy")).route(
            request()
        )
        self.assertEqual(result.route, "ha")
        self.assertEqual(client.post.call_args.args[0], "https://api.openai.com/v1/decisions")
        self.assertFalse(client.post.call_args.kwargs["follow_redirects"])
        with self.assertRaises(ValueError):
            httpx_transport(client, "http://example.org/v1", "dummy")

    async def test_state_context_bound(self):
        state = request_state(request(context=tuple(("user", str(i)) for i in range(20))))
        self.assertEqual(len(state["context"]), 12)
        self.assertNotIn("conversation_id", state)


if __name__ == "__main__":
    unittest.main()
