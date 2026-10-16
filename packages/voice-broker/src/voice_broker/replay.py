"""Offline/shadow comparison. Only aggregate counts and timing; no actuators or text logs."""

import asyncio
import json
import math
import time

from voice_broker.routing import NaiveRouter, RouteRequest

# Synthetic, not household transcripts. Each label is a policy expectation, not a measured model answer.
CASES = [
    ("en-light", "Turn on the lights", "ha", (), "kitchen"),
    ("uk-light", "Увімкни світло", "ha", (), "кухня"),
    ("en-scene", "Activate the Sleep scene", "ha", (), "bedroom"),
    ("uk-scene", "Увімкни режим сну", "ha", (), "спальня"),
    ("en-temp", "What is the bedroom temperature?", "ha", (), "kitchen"),
    ("uk-temp", "Яка температура у спальні?", "ha", (), "кухня"),
    ("en-weather", "What is the weather tomorrow?", "openclaw", (), "kitchen"),
    ("uk-weather", "Яка завтра погода?", "openclaw", (), "кухня"),
    ("en-code", "Write a Python parser", "openclaw", (), "kitchen"),
    ("uk-code", "Напиши код для парсера", "openclaw", (), "кухня"),
    ("en-ambiguous", "Turn it off", "clarify", (), "kitchen"),
    ("uk-ambiguous", "Вимкни це", "clarify", (), "кухня"),
    (
        "en-follow-home",
        "And dim them to 20 percent",
        "ha",
        (("user", "Turn on kitchen lights"), ("assistant", "Kitchen lights are on")),
        "kitchen",
    ),
    (
        "uk-follow-home",
        "А тепер зменш до 20 відсотків",
        "ha",
        (("user", "Увімкни світло на кухні"), ("assistant", "Увімкнено")),
        "кухня",
    ),
    ("en-follow-weather", "And tomorrow?", "openclaw", (("user", "Weather today?"), ("assistant", "Sunny")), "kitchen"),
    (
        "uk-follow-weather",
        "А завтра?",
        "openclaw",
        (("user", "Яка сьогодні погода?"), ("assistant", "Сонячно")),
        "кухня",
    ),
    ("en-follow-empty", "And tomorrow?", "clarify", (), "kitchen"),
    ("uk-follow-empty", "А завтра?", "clarify", (), "кухня"),
    ("en-area", "Close the blinds here", "ha", (), "bedroom"),
    ("uk-area", "Закрий тут штори", "ha", (), "спальня"),
    ("en-mixed", "Turn on the lights and write Python code", "openclaw", (), "kitchen"),
    ("uk-mixed", "Увімкни світло і напиши код", "openclaw", (), "кухня"),
    ("en-scene-knowledge", "What does a movie scene mean?", "openclaw", (), "kitchen"),
    ("uk-scene-knowledge", "Що означає сцена у фільмі?", "openclaw", (), "кухня"),
    ("en-incomplete", "Turn on", "clarify", (), "kitchen"),
    ("uk-incomplete", "Увімкни", "clarify", (), "кухня"),
    ("en-weather-device", "Turn off the weather station display", "ha", (), "kitchen"),
    ("uk-weather-device", "Вимкни дисплей метеостанції", "ha", (), "кухня"),
]


def percentile(values, p):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * p) - 1)] if ordered else None


async def evaluate(router, name, cases=CASES):
    times, correct, unsafe_ha = [], 0, 0
    confusion = {}
    for ident, text, expected, context, area in cases:
        request = RouteRequest(
            text=text, context=context, area=area, device="synthetic-pe", conversation_id="synthetic"
        )
        started = time.perf_counter()
        answer = await router.route(request)
        times.append((time.perf_counter() - started) * 1000)
        correct += answer.route == expected
        unsafe_ha += answer.route == "ha" and expected != "ha"
        key = expected + "->" + answer.route
        confusion[key] = confusion.get(key, 0) + 1
    return {
        "name": name,
        "samples": len(cases),
        "accuracy": correct / len(cases),
        "unsafe_ha": unsafe_ha,
        "p50_ms": percentile(times, 0.5),
        "p95_ms": percentile(times, 0.95),
        "confusion": confusion,
        "mode": "shadow_no_actuators",
        "timing": "wall-clock routing including transport if injected",
    }


def main():
    import argparse
    from pathlib import Path

    parser = argparse.ArgumentParser(description="Synthetic routing comparison; NEVER invokes a backend or speaker")
    parser.add_argument(
        "--config", type=Path, help="Broker configuration including explicit classifier and credential file references"
    )
    parser.add_argument(
        "--allow-api", action="store_true", help="Permit at most --limit synthetic classifier API calls"
    )
    parser.add_argument("--limit", type=int, default=len(CASES))
    args = parser.parse_args()
    if not 1 <= args.limit <= len(CASES):
        parser.error("limit must be between 1 and 28")
    if args.config and not args.allow_api:
        parser.error("--config requires explicit --allow-api; default replay is local and free")

    async def run():
        if args.config:
            import httpx2

            from .config import load
            from .router_factory import make_router

            config = load(args.config)
            if config.routing is None:
                raise ValueError("configuration must select a router explicitly")
            async with httpx2.AsyncClient(timeout=2, follow_redirects=False) as http:
                router = make_router(config.routing, config.openai_api_key, http)
                return await evaluate(router, config.routing.strategy, CASES[: args.limit])
        return await evaluate(NaiveRouter(), "naive-synthetic-offline", CASES[: args.limit])

    print(json.dumps(asyncio.run(run()), indent=2))


if __name__ == "__main__":
    main()
