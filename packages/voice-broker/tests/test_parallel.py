"""GPT-Live beside Home Assistant: a scripted Live connection and a scripted Home Assistant listener."""

from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from types import SimpleNamespace

import numpy as np
import pytest
from test_live import Connection, Host, nothing_recent, settle
from voice_broker import live
from voice_broker.assist import HeardSpeech, HomeTurn, Outcome, ToolUse, Unavailable
from voice_broker.config import Live
from voice_broker.live import LiveSession, Parallel
from voice_broker.openclaw import ConsultFailed
from voice_broker.protocol import Phase
from voice_broker.routing import RouteDecision, RouteRequest


class Ears:
    """Home Assistant listening, as the session sees it: audio in, scripted turns out."""

    def __init__(self) -> None:
        self.events: asyncio.Queue = asyncio.Queue()
        self.fed: list[tuple[int, bool]] = []
        # What each user transcript fragment told it: how long ago speech over the assistant began, or None.
        self.heard: list[float | None] = []
        self.during: list[bool] = []
        self.started = False
        self.stopped = False
        self.finishing: asyncio.Task | None = None

    def feed(self, pcm: np.ndarray, audible: bool) -> None:
        self.fed.append((len(pcm), audible))

    def user_heard(self, back_s: float | None, during: bool = False) -> None:
        self.heard.append(back_s)
        self.during.append(during)

    def start(self) -> None:
        self.started = True

    def stop(self):
        self.stopped = True
        return self.finishing

    def hears(self, turn: int) -> None:
        self.events.put_nowait(HeardSpeech(turn))

    def did(
        self,
        turn: int,
        outcome: Outcome,
        speech: str = "",
        tools=(),
        heard="turn on the kitchen light",
        reason="",
        asks=False,
        gap=None,
    ):
        self.events.put_nowait(HomeTurn(turn, outcome, speech, heard, tuple(tools), 1000, 9000, reason, asks, gap))


class Conn(Connection):
    def __init__(self) -> None:
        super().__init__()
        self.thinking: list[dict] = []
        self.instructions: list[dict] = []
        self.session.thinking = SimpleNamespace(append=self._think)
        self.session.instructions = SimpleNamespace(append=self._instruct)

    async def _think(self, **kwargs) -> None:
        self.thinking.append(kwargs)

    async def _instruct(self, **kwargs) -> None:
        self.instructions.append(kwargs)

    def assistant(self, text: str, start_ms: int, end_ms: int) -> None:
        self.events.put_nowait(
            SimpleNamespace(type="session.output_transcript.delta", delta=text, start_ms=start_ms, end_ms=end_ms)
        )


class Agent:
    def __init__(self, *answers, delay: float = 0.0) -> None:
        self.answers = list(answers)
        self.tasks: list[str] = []
        self.delay = delay

    async def consult(self, task: str) -> str:
        self.tasks.append(task)
        await asyncio.sleep(self.delay)
        answer = self.answers.pop(0)
        if isinstance(answer, Exception):
            raise answer
        return answer


@pytest.fixture(autouse=True)
def quick(monkeypatch):
    monkeypatch.setattr(live, "_CLAIM_GRACE_S", 0.02)
    monkeypatch.setattr(live, "_COMBINE_WAIT_S", 0.1)


async def run(script, ears: Ears, agent: Agent, observe=None, shadow=None, host: Host | None = None) -> Conn:
    conn = Conn()

    @asynccontextmanager
    async def connect():
        yield conn

    session = LiveSession(
        Live(model="gpt-live-1", voice="marin", instructions=""),
        "Kitchen",
        agent.consult,
        nothing_recent,
        connect,
        None,
        Parallel(ears, observe, shadow),
    )
    async with session.open(host or Host()):
        receiving = asyncio.create_task(session.receive())
        await script(conn, session)
        await quiet(session)
        await conn.events.put(None)
        await receiving
    return conn


async def quiet(session: LiveSession) -> None:
    await settle()
    async with asyncio.timeout(3):
        while session.busy or session._observing is not None and not session._observing.done():
            await asyncio.sleep(0.005)
    await asyncio.sleep(0.05)


def told(conn: Conn) -> list[tuple[str | None, str]]:
    return [(c["delegation_id"], c["content"]) for c in conn.commentary]


ON = [ToolUse("intent__HassTurnOn", {"area": "Kitchen", "domain": "light"}, False)]


def test_a_home_request_live_does_not_delegate_reaches_it_from_home_assistant_alone():
    ears, agent = Ears(), Agent()

    async def script(conn: Conn, session: LiveSession) -> None:
        conn.user("Turn on the kitchen light.")
        ears.hears(1)
        await settle()
        assert session.busy  # the conversation stays open for Home Assistant's result
        ears.did(1, Outcome.ACTED, "The kitchen light is on.", ON)

    conn = asyncio.run(run(script, ears, agent))
    assert told(conn) == [(None, "Home Assistant: The kitchen light is on.")]
    assert agent.tasks == []
    assert ears.started and ears.stopped and ears.heard == [None]


def test_a_delegation_claims_the_home_turn_under_way_and_tells_both_results_once():
    """Mixed: Home Assistant does the home clause, the agent the rest, GPT-Live hears one answer."""
    ears, agent = Ears(), Agent("Tomorrow brings rain after four.", delay=0.02)

    async def script(conn: Conn, session: LiveSession) -> None:
        conn.user("Turn on the kitchen light and tell me if it rains tomorrow.")
        ears.hears(1)
        await settle()
        conn.delegate("dlg_1")
        await settle()
        ears.did(1, Outcome.ACTED, "The kitchen light is on.", ON)

    conn = asyncio.run(run(script, ears, agent))
    (answer,) = told(conn)
    assert answer[0] == "dlg_1"
    assert "Home Assistant: The kitchen light is on." in answer[1]
    assert "Tomorrow brings rain after four." in answer[1]
    # The agent gets the transcript, never the home's result to act on.
    (task,) = agent.tasks
    assert "kitchen light" in task and "The kitchen light is on" not in task


def test_a_slow_home_assistant_never_holds_the_agents_answer_for_long():
    ears, agent = Ears(), Agent("It is 14:05.")

    async def script(conn: Conn, session: LiveSession) -> None:
        conn.user("Turn on the light, and what time is it?")
        ears.hears(1)
        await settle()
        conn.delegate("dlg_1")
        await asyncio.sleep(0.3)  # past _COMBINE_WAIT_S
        ears.did(1, Outcome.ACTED, "The light is on.", ON)

    conn = asyncio.run(run(script, ears, agent))
    first, second = told(conn)
    assert first[0] == "dlg_1" and "It is 14:05." in first[1] and live._HOME_PENDING in first[1]
    # Its result follows on its own, exactly once.
    assert second == (None, "Home Assistant: The light is on.")


def test_a_non_home_request_goes_to_the_agent_and_home_assistants_abstention_is_never_spoken():
    ears, agent = Ears(), Agent("Rain after four.")

    async def script(conn: Conn, session: LiveSession) -> None:
        conn.user("Will it rain tomorrow?")
        ears.hears(1)
        await settle()
        conn.delegate("dlg_1")
        await settle()
        ears.did(1, Outcome.ABSTAINED, "That is not a home request.")

    conn = asyncio.run(run(script, ears, agent))
    assert told(conn) == [("dlg_1", "Rain after four.")]


def test_home_assistants_question_is_asked_and_the_answer_is_home_assistants():
    """Which light? -> Kitchen. The answer is Home Assistant's next turn: no delegation, no agent."""
    ears, agent = Ears(), Agent()

    async def script(conn: Conn, session: LiveSession) -> None:
        conn.user("Turn on the light.")
        ears.hears(1)
        ears.did(1, Outcome.ASKED, "Which light, the kitchen or the hallway?")
        await quiet(session)
        conn.user("Kitchen.")
        ears.hears(2)
        ears.did(2, Outcome.ACTED, "The kitchen light is on.", ON, heard="kitchen")

    conn = asyncio.run(run(script, ears, agent))
    question, result = told(conn)
    assert question[0] is None and "Which light, the kitchen or the hallway?" in question[1]
    assert "don't delegate it" in question[1]
    assert result == (None, "Home Assistant: The kitchen light is on.")
    assert agent.tasks == []


def test_an_uncertain_turn_is_told_as_such_and_a_failure_only_as_silent_context():
    ears, agent = Ears(), Agent()

    async def script(conn: Conn, session: LiveSession) -> None:
        ears.hears(1)
        ears.did(1, Outcome.UNCERTAIN, reason="intent-failed")
        ears.hears(2)
        ears.did(2, Outcome.FAILED, reason="stt-no-text-recognized")

    conn = asyncio.run(run(script, ears, agent))
    assert told(conn) == [(None, live._HOME_UNCERTAIN)]
    (silent,) = conn.thinking
    assert silent["delegation_id"] is None and "stt-no-text-recognized" in silent["content"]


def test_unavailable_home_assistant_is_told_once_and_the_agent_never_stands_in_for_it():
    ears, agent = Ears(), Agent("I can't control the home; Home Assistant handles that.")

    async def script(conn: Conn, session: LiveSession) -> None:
        ears.events.put_nowait(Unavailable("0 pipelines named 'Voice broker home'"))
        await settle()
        conn.user("Turn on the kitchen light.")
        conn.delegate("dlg_1")

    conn = asyncio.run(run(script, ears, agent))
    (note,) = conn.instructions
    assert (
        note["delegation_id"] is None
        and "unavailable" in note["content"]
        and "never say it was done" in note["content"]
    )
    # The delegation is the agent's as always; its task is the same transcript, with no home handoff.
    assert told(conn) == [("dlg_1", "I can't control the home; Home Assistant handles that.")]


def test_the_mic_reaches_home_assistant_with_whether_the_assistant_was_audible():
    ears, agent = Ears(), Agent()
    host = Host()

    async def script(conn: Conn, session: LiveSession) -> None:
        await session.on_mic(np.zeros(160, np.int16))
        host.assistant_audible = True
        await session.on_mic(np.zeros(160, np.int16))

    asyncio.run(run(script, ears, agent, host=host))
    assert ears.fed == [(160, False), (160, True)]


def test_an_action_is_observed_and_a_discrepancy_is_told_without_any_undo():
    ears, agent = Ears(), Agent()
    evidence: list[str] = []

    async def observe(text: str) -> str | None:
        evidence.append(text)
        return "The hallway light came on instead of the kitchen's."

    async def script(conn: Conn, session: LiveSession) -> None:
        conn.user("Turn on the kitchen light.")
        ears.hears(1)
        ears.did(1, Outcome.ACTED, "Done.", ON)

    conn = asyncio.run(run(script, ears, agent, observe=observe))
    (text,) = evidence
    assert "Turn on the kitchen light." in text and "intent__HassTurnOn" in text
    assert told(conn)[-1][0] is None and "hallway light came on" in told(conn)[-1][1]
    assert "reaches Home Assistant by itself" in told(conn)[-1][1]
    assert agent.tasks == []


def test_only_actions_are_observed_and_a_newer_action_drops_an_older_check():
    ears, agent = Ears(), Agent()
    checked: list[str] = []
    first_released = asyncio.Event()

    async def observe(text: str) -> str | None:
        checked.append(text)
        if len(checked) == 1:
            await first_released.wait()
            return "Stale discrepancy."
        return None

    async def script(conn: Conn, session: LiveSession) -> None:
        ears.hears(1)
        ears.did(1, Outcome.ANSWERED, "It is 21 degrees.", [ToolUse("homeassistant__GetLiveContext", {}, False)])
        ears.hears(2)
        ears.did(2, Outcome.ACTED, "On.", ON)
        await settle()
        ears.hears(3)
        ears.did(3, Outcome.ACTED, "Off.", [ToolUse("intent__HassTurnOff", {}, False)])
        await settle()
        first_released.set()

    conn = asyncio.run(run(script, ears, agent, observe=observe))
    assert len(checked) == 2  # the answer is not observed
    assert all("Stale discrepancy" not in content for _, content in told(conn))


def test_a_failed_observation_tells_nothing():
    ears, agent = Ears(), Agent()

    async def observe(text: str) -> str | None:
        raise ConsultFailed("timeout")

    async def script(conn: Conn, session: LiveSession) -> None:
        ears.hears(1)
        ears.did(1, Outcome.ACTED, "On.", ON)

    conn = asyncio.run(run(script, ears, agent, observe=observe))
    assert told(conn) == [(None, "Home Assistant: On.")]


def test_the_decisions_shadow_only_logs_even_when_it_fails(caplog):
    ears, agent = Ears(), Agent("Rain.", "Sun.")
    requests: list[RouteRequest] = []

    async def shadow(request: RouteRequest) -> RouteDecision:
        requests.append(request)
        if len(requests) == 2:
            raise RuntimeError("Decisions is down: will it be sunny")
        return RouteDecision("ha", 0.9, 300.0)

    async def script(conn: Conn, session: LiveSession) -> None:
        conn.user("Will it rain?")
        conn.delegate("dlg_1")
        await quiet(session)
        conn.user("Will it be sunny?")
        conn.delegate("dlg_2")

    caplog.set_level("INFO")
    conn = asyncio.run(run(script, ears, agent, shadow=shadow))
    # Its "ha" changes nothing: the agent answered both.
    assert told(conn) == [("dlg_1", "Rain."), ("dlg_2", "Sun.")]
    assert [r.text for r in requests] == ["Will it rain?", "Will it be sunny?"]
    assert "shadow classification: ha" in caplog.text
    # A failure is logged by class, never with its message, which can quote speech.
    assert (
        "shadow classification failed: RuntimeError" in caplog.text
        and "sunny" not in caplog.text.split("failed")[1][:40]
    )


def test_a_turn_finishing_after_the_conversation_is_kept_until_done():
    ears, agent = Ears(), Agent()

    async def main():
        ears.finishing = asyncio.create_task(asyncio.sleep(0.05))

        async def script(conn: Conn, session: LiveSession) -> None:
            pass

        await run(script, ears, agent)
        assert ears.finishing in live._FINISHING
        await ears.finishing
        await settle()
        assert ears.finishing not in live._FINISHING

    asyncio.run(main())


def test_a_silent_home_assistant_result_after_playback_leaves_the_speaker_listening():
    ears, agent = Ears(), Agent()
    host = Host()

    async def script(conn: Conn, session: LiveSession) -> None:
        # Small talk: GPT-Live answers itself while Home Assistant still works on the same words.
        ears.hears(1)
        await settle()
        ears.did(1, Outcome.ABSTAINED)

    asyncio.run(run(script, ears, agent, host=host))
    assert host.phases and host.phases[-1] == Phase.LISTENING


def test_an_action_with_a_follow_up_question_is_told_as_the_question():
    ears, agent = Ears(), Agent()

    async def script(conn: Conn, session: LiveSession) -> None:
        ears.hears(1)
        ears.did(1, Outcome.ACTED, "Done. Anything else?", tools=ON, asks=True)

    conn = asyncio.run(run(script, ears, agent))
    (said,) = [content for _, content in told(conn)]
    assert said.startswith("Home Assistant asks: Done. Anything else?")
    assert "don't delegate it" in said


def test_whether_the_user_spoke_over_the_assistant_is_judged_on_lives_own_timeline():
    ears, agent = Ears(), Agent()

    async def script(conn: Conn, session: LiveSession) -> None:
        conn.user("Turn on the", start_ms=1000)  # nobody else speaking
        conn.assistant("Sure,", 2000, 3000)
        # The end of the user's request, transcribed after the assistant began: it started before.
        conn.user(" light.", start_ms=1500)
        conn.user("No, wait", start_ms=2500)  # over the assistant
        conn.user("stop", start_ms=4200)  # just after its speech, which the speaker still plays out
        conn.user("Thanks.", start_ms=6000)  # well after
        # A long reply stamped far ahead of the user's audio: the time ago follows the user's own
        # fragments, never the assistant's stamps.
        conn.assistant("Here is a long story.", 7000, 20000)
        conn.user("Enough", start_ms=9900)
        conn.user(" already.", start_ms=7000)  # a fragment of speech that began earlier, delivered late
        await settle()

    asyncio.run(run(script, ears, agent))
    # At least the transcript's assumed lag; more when the user's own fragments show more.
    assert ears.heard == [None, None, 2.5, 2.5, None, 2.5, 3.0]
    # Within the assistant's speech itself, or in the moments after it the speaker still plays it out.
    assert ears.during == [False, False, True, False, False, True, True]


def test_a_home_result_is_told_at_once_while_a_slow_consult_runs_on():
    """Home Assistant acted: a consult of up to 90 s must not keep the user from hearing so."""
    ears, agent = Ears(), Agent("It is 14:05.", delay=0.5)

    async def script(conn: Conn, session: LiveSession) -> None:
        conn.user("Turn on the light, and what time is it?")
        ears.hears(1)
        await settle()
        conn.delegate("dlg_1")
        await settle()
        ears.did(1, Outcome.ACTED, "The light is on.", ON)
        await asyncio.sleep(0.3)  # past _COMBINE_WAIT_S, the consult still running
        assert told(conn) == [(None, "Home Assistant: The light is on.")]

    conn = asyncio.run(run(script, ears, agent))
    # The agent's answer follows, without telling the home's result again.
    assert told(conn) == [(None, "Home Assistant: The light is on."), ("dlg_1", "It is 14:05.")]


def test_the_pieces_of_one_cut_utterance_are_told_as_one_failure():
    ears, agent = Ears(), Agent("Sure.")

    async def script(conn: Conn, session: LiveSession) -> None:
        conn.user("Turn on the kitchen light.")
        for turn in (1, 2, 3):
            ears.hears(turn)
        await settle()
        conn.delegate("dlg_1")
        await settle()
        ears.did(1, Outcome.FAILED, reason="audio backlog", gap=1)
        ears.did(2, Outcome.FAILED, reason="speech cut", gap=1)
        ears.did(3, Outcome.FAILED, reason="speech cut", gap=1)

    conn = asyncio.run(run(script, ears, agent))
    ((delegation, answer),) = told(conn)
    # One cut, told once: the pieces after its first are the same utterance.
    assert delegation == "dlg_1" and "(audio backlog)" in answer and "(speech cut)" not in answer


def test_a_consult_that_breaks_leaves_no_home_result_untold():
    ears, agent = Ears(), Agent(RuntimeError("bug"), delay=0.02)

    async def script(conn: Conn, session: LiveSession) -> None:
        conn.user("Turn on the light, and what time is it?")
        ears.hears(1)
        await settle()
        conn.delegate("dlg_1")
        await settle()
        ears.did(1, Outcome.ACTED, "The light is on.", ON)

    conn = asyncio.run(run(script, ears, agent))
    assert (None, "Home Assistant: The light is on.") in told(conn)


def test_each_cut_is_told_once_on_its_own_and_a_separate_one_again():
    ears, agent = Ears(), Agent()

    async def script(conn: Conn, session: LiveSession) -> None:
        for turn, gap in ((1, 1), (2, 1), (3, 1), (4, 2)):
            ears.hears(turn)
            ears.did(turn, Outcome.FAILED, reason="speech cut", gap=gap)
        await settle()

    conn = asyncio.run(run(script, ears, agent))
    # Two cuts, the second a separate request that failed the same way: both told.
    assert len(conn.thinking) == 2 and all("speech cut" in t["content"] for t in conn.thinking)
