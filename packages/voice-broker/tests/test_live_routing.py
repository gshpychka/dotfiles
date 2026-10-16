"""Routed delegation: a scripted Live connection, a scripted classifier and fake backends."""

from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from types import SimpleNamespace

from test_live import Connection, Host, nothing_recent, settle
from voice_broker.config import Live
from voice_broker.home_assistant import HomeAssistantFailed, HomeReply
from voice_broker.live import LiveSession, Routed
from voice_broker.openclaw import ConsultFailed
from voice_broker.protocol import Phase
from voice_broker.routing import RouteDecision, RouteRequest, RoutingFailed


def assistant(conn: Connection, text: str) -> None:
    """Live speaking, as its output transcript."""
    conn.events.put_nowait(SimpleNamespace(type="session.output_transcript.delta", delta=text))


class Backends:
    """Records every classification and backend call; answers from scripts."""

    def __init__(self, routes, home_replies=(), answers=()) -> None:
        self.routes = list(routes)
        self.home_replies = list(home_replies)
        self.answers = list(answers)
        self.requests: list[RouteRequest] = []
        self.home: list[tuple[str, str | None]] = []
        self.tasks: list[str] = []

    async def route(self, request: RouteRequest) -> RouteDecision:
        self.requests.append(request)
        route = self.routes.pop(0)
        if isinstance(route, Exception):
            raise route
        return RouteDecision(route, 0.9, 1.0)

    async def converse(self, text: str, conversation_id: str | None) -> HomeReply:
        self.home.append((text, conversation_id))
        reply = self.home_replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return reply

    async def consult(self, task: str) -> str:
        self.tasks.append(task)
        answer = self.answers.pop(0)
        if isinstance(answer, Exception):
            raise answer
        return answer

    def routed(self, pending_question_s: float = 60.0) -> Routed:
        return Routed(self.route, self.converse, pending_question_s, settle_s=0.01)


def asks(question: str, conversation_id: str = "01JHA") -> HomeReply:
    return HomeReply(question, conversation_id, continue_conversation=True)


def done(speech: str, conversation_id: str = "01JHA") -> HomeReply:
    return HomeReply(speech, conversation_id, continue_conversation=False)


async def run(script, backends: Backends, area: str = "Kitchen", routed: Routed | None = None) -> Connection:
    conn = Connection()

    @asynccontextmanager
    async def connect():
        yield conn

    session = LiveSession(
        Live(model="gpt-live-1", voice="marin", instructions=""),
        area,
        backends.consult,
        nothing_recent,
        connect,
        None,
        routed or backends.routed(),
    )
    async with session.open(Host()):
        receiving = asyncio.create_task(session.receive())
        await script(conn, session)
        await idle(session)
        await conn.events.put(None)
        await receiving
    return conn


async def idle(session: LiveSession) -> None:
    await settle()
    while session.busy:
        await asyncio.sleep(0.005)


def spoken(conn: Connection) -> list[str]:
    return [c["content"] for c in conn.commentary]


def test_a_question_from_home_assistant_is_asked_and_its_answer_continues_the_same_conversation():
    backends = Backends(
        routes=["ha", "ha"],
        home_replies=[asks("Which light, the kitchen or the hallway?", "01JQ"), done("The kitchen light is on.")],
    )

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn on the light.")
        conn.delegate("dlg_1")
        await idle(session)
        # Live speaks the question, as its own words.
        assistant(conn, "Which light, the kitchen or the hallway?")
        conn.user("Kitchen.")
        conn.delegate("dlg_2")

    conn = asyncio.run(run(script, backends))

    assert backends.home == [("Turn on the light.", None), ("Kitchen.", "01JQ")]
    first, second = backends.requests
    assert first.pending_question is None
    # The answer is classified knowing what Home Assistant asked, and what was said.
    assert second.pending_question == "Which light, the kitchen or the hallway?"
    assert second.context == (
        ("user", "Turn on the light."),
        ("assistant", "Which light, the kitchen or the hallway?"),
    )
    question, result = conn.commentary
    assert question["delegation_id"] == "dlg_1" and "Which light, the kitchen or the hallway?" in question["content"]
    assert "delegate their answer" in question["content"]
    assert result == {"content": "The kitchen light is on.", "delegation_id": "dlg_2"}
    assert backends.tasks == []


def test_a_yes_answers_home_assistants_question():
    backends = Backends(
        routes=["ha", "ha"],
        home_replies=[asks("It's 17 degrees in the kitchen. Shall I turn the heating up?"), done("Heating set.")],
    )

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("How warm is it in here?")
        conn.delegate("dlg_1")
        await idle(session)
        conn.user("Yes.")
        conn.delegate("dlg_2")

    asyncio.run(run(script, backends))

    assert backends.home[1] == ("Yes.", "01JHA")


def test_a_change_of_topic_goes_to_openclaw_and_drops_the_question():
    backends = Backends(
        routes=["ha", "openclaw", "ha"],
        home_replies=[asks("Which light?"), done("Done.", "01JNEW")],
        answers=["Rain after four."],
    )

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn on the light.")
        conn.delegate("dlg_1")
        await idle(session)
        conn.user("Actually, will it rain today?")
        conn.delegate("dlg_2")
        await idle(session)
        conn.user("Turn on the hallway light.")
        conn.delegate("dlg_3")

    conn = asyncio.run(run(script, backends))

    assert "user: Actually, will it rain today?" in backends.tasks[0]
    assert "Turn on the light." not in backends.tasks[0]
    # The later home request starts a new Home Assistant conversation.
    assert backends.home[1] == ("Turn on the hallway light.", None)
    assert backends.requests[2].pending_question is None
    assert spoken(conn)[1] == "Rain after four."


def test_a_clarification_drops_the_question_and_runs_nothing():
    backends = Backends(routes=["ha", "clarify", "ha"], home_replies=[asks("Which light?"), done("Done.")])

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn on the light.")
        conn.delegate("dlg_1")
        await idle(session)
        conn.user("Never mind.")
        conn.delegate("dlg_2")
        await idle(session)
        conn.user("Turn on the lamp.")
        conn.delegate("dlg_3")

    conn = asyncio.run(run(script, backends))

    assert len(backends.home) == 2 and backends.home[1] == ("Turn on the lamp.", None)
    assert spoken(conn)[1].startswith("Nothing was done")


def test_an_expired_question_is_not_continued():
    backends = Backends(routes=["ha", "ha"], home_replies=[asks("Which light?"), done("Done.")])

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn on the light.")
        conn.delegate("dlg_1")
        await idle(session)
        await asyncio.sleep(0.06)
        conn.user("Kitchen.")
        conn.delegate("dlg_2")

    asyncio.run(run(script, backends, routed=backends.routed(pending_question_s=0.05)))

    assert backends.home[1] == ("Kitchen.", None)
    assert backends.requests[1].pending_question is None


def test_a_home_assistant_failure_drops_the_question_and_is_never_replayed():
    backends = Backends(
        routes=["ha", "ha", "ha"],
        home_replies=[asks("Which light?"), HomeAssistantFailed("TimeoutError"), done("Done.")],
    )

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn on the light.")
        conn.delegate("dlg_1")
        await idle(session)
        conn.user("Kitchen.")
        conn.delegate("dlg_2")
        await idle(session)
        conn.user("Is it on?")
        conn.delegate("dlg_3")

    conn = asyncio.run(run(script, backends))

    assert "may have acted" in spoken(conn)[1]
    # Neither the failed request nor the old conversation is sent again.
    assert backends.home[2] == ("Is it on?", None)
    assert backends.tasks == []


def test_a_routing_failure_runs_no_backend():
    backends = Backends(routes=[RoutingFailed("PermissionDeniedError"), "ha"], home_replies=[done("Done.")])

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn off the lights.")
        conn.delegate("dlg_1")
        await idle(session)
        conn.user("Turn off the lights.")
        conn.delegate("dlg_2")

    conn = asyncio.run(run(script, backends))

    assert spoken(conn)[0].startswith("Nothing was done")
    assert backends.tasks == []
    # Only the repeated request ran, once.
    assert backends.home == [("Turn off the lights.", None)]


def test_an_unexpected_classifier_error_also_fails_closed():
    backends = Backends(routes=[RuntimeError("bug")])

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn off the lights.")
        conn.delegate("dlg_1")

    conn = asyncio.run(run(script, backends))

    assert spoken(conn)[0].startswith("Nothing was done") and backends.home == [] and backends.tasks == []


def test_a_mixed_request_reaches_openclaw_whole():
    backends = Backends(routes=["openclaw"], answers=["Lights dimmed; here are the headlines."])

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Dim the lights")
        conn.user(" and read me today's headlines.")
        conn.delegate("dlg_1")

    asyncio.run(run(script, backends))

    (task,) = backends.tasks
    assert "user: Dim the lights and read me today's headlines." in task
    assert backends.home == []


def test_a_failed_consult_is_not_carried_into_the_next_request():
    backends = Backends(routes=["openclaw", "openclaw"], answers=[ConsultFailed("gateway down"), "Sent."])

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Email Maria the list.")
        conn.delegate("dlg_1")
        await idle(session)
        conn.user("Text Ivan I'm late.")
        conn.delegate("dlg_2")

    conn = asyncio.run(run(script, backends))

    assert "gateway down" in spoken(conn)[0]
    assert "Email Maria" not in backends.tasks[1]


def test_speech_still_arriving_is_not_run_until_the_next_delegation():
    backends = Backends(routes=["openclaw"], answers=["Reminder set."])
    words = ["Remind", " me", " to", " call", " the", " plumber", " tomorrow", " at", " nine."]

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.delegate("dlg_1")
        # One fragment per settle window for longer than the settling wait lasts.
        for _ in range(30):
            for word in words:
                conn.user(word)
                await asyncio.sleep(0.009)
        await idle(session)
        conn.delegate("dlg_2")

    conn = asyncio.run(run(script, backends, routed=Routed(backends.route, backends.converse, 60.0, settle_s=0.02)))

    assert spoken(conn)[0].startswith("Nothing was done yet")
    (task,) = backends.tasks
    # The whole utterance, its start included, reached the one consult.
    assert task.count("Remind me to call the plumber") == 30


def test_questions_do_not_cross_speakers():
    kitchen = Backends(routes=["ha"], home_replies=[asks("Which light?", "01JKITCHEN")])
    room = Backends(routes=["ha"], home_replies=[done("Done.", "01JROOM")])

    async def ask(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn on the light.")
        conn.delegate("dlg_k")

    async def answer(conn: Connection, session: LiveSession) -> None:
        conn.user("Kitchen.")
        conn.delegate("dlg_r")

    async def both() -> None:
        await run(ask, kitchen, "Kitchen")
        await run(answer, room, "Room")

    asyncio.run(both())

    assert room.home == [("Kitchen.", None)]
    (request,) = room.requests
    assert request.pending_question is None and request.context == () and request.area == "Room"


def test_a_new_conversation_does_not_inherit_a_question():
    backends = Backends(routes=["ha", "ha"], home_replies=[asks("Which light?"), done("Done.")])

    async def ask(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn on the light.")
        conn.delegate("dlg_1")

    async def answer(conn: Connection, session: LiveSession) -> None:
        conn.user("Kitchen.")
        conn.delegate("dlg_1")

    async def reconnect() -> None:
        await run(ask, backends)
        await run(answer, backends)

    asyncio.run(reconnect())

    assert backends.home[1] == ("Kitchen.", None)


def test_ending_the_conversation_mid_request_cancels_it():
    started = asyncio.Event()
    cancelled = []

    async def converse(text: str, conversation_id: str | None) -> HomeReply:
        started.set()
        try:
            await asyncio.Event().wait()
        except asyncio.CancelledError:
            cancelled.append(text)
            raise
        raise AssertionError

    backends = Backends(routes=["ha"])

    async def main() -> Connection:
        conn = Connection()

        @asynccontextmanager
        async def connect():
            yield conn

        session = LiveSession(
            Live(model="gpt-live-1", voice="marin", instructions=""),
            "Kitchen",
            backends.consult,
            nothing_recent,
            connect,
            None,
            Routed(backends.route, converse, 60.0, 0.01),
        )
        async with session.open(Host()):
            receiving = asyncio.create_task(session.receive())
            conn.user("Turn on the light.")
            conn.delegate("dlg_1")
            await started.wait()
            await conn.events.put(None)
            await receiving
        await asyncio.sleep(0)
        return conn

    conn = asyncio.run(main())

    assert cancelled == ["Turn on the light."] and conn.commentary == []


def test_the_user_text_alone_reaches_home_assistant():
    backends = Backends(routes=["ha"], home_replies=[done("Done.")])

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn")
        assistant(conn, "Mm-hm.")
        conn.user(" off the fan.")
        conn.delegate("dlg_1")

    asyncio.run(run(script, backends))

    # No speaker, area, history or assistant words: Home Assistant places it by the device.
    assert backends.home == [("Turn off the fan.", None)]


def test_a_transcript_trailing_the_classification_is_routed_whole():
    backends = Backends(routes=["ha", "openclaw"], answers=["Done, and rain after four."])
    routed_once = asyncio.Event()

    async def route(request: RouteRequest) -> RouteDecision:
        decision = await backends.route(request)
        routed_once.set()
        # The rest of the utterance, spoken before the delegation, is transcribed now.
        await asyncio.sleep(0.02)
        return decision

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn off the kitchen light", start_ms=100)
        conn.delegate("dlg_1")
        await routed_once.wait()
        conn.user(" and tell me if it'll rain.", start_ms=150)

    conn = asyncio.run(run(script, backends, routed=Routed(route, backends.converse, 60.0, settle_s=0.01)))

    # Classified again with the whole request, then run once, on OpenClaw alone.
    assert [r.text for r in backends.requests] == [
        "Turn off the kitchen light",
        "Turn off the kitchen light and tell me if it'll rain.",
    ]
    assert backends.home == [] and len(backends.tasks) == 1
    assert spoken(conn) == ["Done, and rain after four."]


def test_speech_after_the_delegation_is_not_part_of_its_request():
    backends = Backends(routes=["ha", "openclaw"], home_replies=[done("Light off.")], answers=["Rain after four."])
    routed_once = asyncio.Event()

    async def route(request: RouteRequest) -> RouteDecision:
        decision = await backends.route(request)
        routed_once.set()
        await asyncio.sleep(0.02)
        return decision

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn off the kitchen light.")
        conn.delegate("dlg_1")
        await routed_once.wait()
        # A new request, spoken after the delegation.
        conn.user("Will it rain?")
        conn.delegate("dlg_2")

    conn = asyncio.run(run(script, backends, routed=Routed(route, backends.converse, 60.0, settle_s=0.01)))

    assert backends.home == [("Turn off the kitchen light.", None)]
    assert "user: Will it rain?" in backends.tasks[0] and "kitchen" not in backends.tasks[0]
    assert conn.commentary == [
        {"content": "Light off.", "delegation_id": "dlg_2"},
        {"content": "Rain after four.", "delegation_id": "dlg_2"},
    ]


def test_the_speaker_listens_again_after_every_kind_of_answer():
    for routes, replies in (
        (["ha"], [done("Done.")]),
        (["clarify"], []),
        ([RoutingFailed("x")], []),
        (["ha"], [HomeAssistantFailed("x")]),
    ):
        backends = Backends(routes=routes, home_replies=replies)
        host = Host()
        conn = Connection()

        @asynccontextmanager
        async def connect(conn=conn):
            yield conn

        async def main(backends=backends, host=host, conn=conn, connect=connect) -> None:
            session = LiveSession(
                Live(model="gpt-live-1", voice="marin", instructions=""),
                "Kitchen",
                backends.consult,
                nothing_recent,
                connect,
                None,
                backends.routed(),
            )
            async with session.open(host):
                receiving = asyncio.create_task(session.receive())
                conn.user("Turn off the fan.")
                conn.delegate("dlg_1")
                await idle(session)
                await conn.events.put(None)
                await receiving

        asyncio.run(main())

        assert host.phases[-1] == Phase.LISTENING, routes
