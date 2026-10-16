"""Pre-execution routing. A route never executes or probes either backend."""

from __future__ import annotations

import re
import time
from dataclasses import dataclass
from typing import Literal, Protocol

from .openclaw import Turn

Route = Literal["ha", "openclaw", "clarify"]


@dataclass(frozen=True, slots=True)
class RouteRequest:
    text: str
    context: tuple[Turn, ...]
    area: str
    device: str
    conversation_id: str
    # Optional untrusted metadata, NOT classifier evidence or HA authorization.
    speaker_advisory: str = ""


@dataclass(frozen=True, slots=True)
class RouteDecision:
    route: Route
    elapsed_ms: float = 0.0


class Router(Protocol):
    async def route(self, request: RouteRequest) -> RouteDecision: ...


class NaiveRouter:
    """Deliberately simple comparison baseline, NOT a semantic classifier.

    Explicit household vocabulary goes to HA; generic requests to OpenClaw.
    Short anaphoric replies and incomplete/mixed commands ask for clarification.
    Never infer HA ownership from an LLM-backed Assist success response.
    """

    async def route(self, request: RouteRequest) -> RouteDecision:
        started = time.monotonic()
        text = request.text.strip().casefold()
        home = re.search(
            r"\b(lights?|lamps?|fan|thermostat|temperature|scene|sleep|blinds?|heating|humidity)\b"
            r"|світл|ламп|вентилятор|термостат|температур|сцен[ауи]|штор|опален|волог|режим сну",
            text,
        )
        generic = re.search(
            r"\b(code|python|git|implement|remember|remind|weather|forecast)\b"
            r"|код|запам.ят|нагада|погод|прогноз",
            text,
        )
        ambiguous = (
            not text
            or bool(
                re.search(
                    r"^(yes|no|do it|that one|and tomorrow|turn (on|off)|так|ні|зроби це|а завтра|увімкни|вимкни)[.!?]?$",
                    text,
                )
            )
            or bool(re.search(r"\b(and|or|the|to)\s*$|(?: і| або| та)\s*$", text))
        )
        route: Route = "clarify" if ambiguous or (home and generic) else "ha" if home else "openclaw"
        return RouteDecision(route, (time.monotonic() - started) * 1000)
