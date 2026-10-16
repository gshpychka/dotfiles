{ config, ... }:
{
  my.voice-broker = {
    enable = true;
    sopsFile = ../../secrets/hoard/voice-broker.yaml;
    recordings.enable = false;
    homeAssistant.url = "http://homeassistant.${config.my.domain}:8123";
    routing = {
      enable = true;
      # "Remote" (conversation.chatgpt, an LLM agent that can ask which device
      # is meant), Home Assistant's preferred pipeline as of 2026-10-16
      # (assist_pipeline/pipeline/list). The Voice PEs' own pipeline selects
      # don't apply: the broker, not the satellite, runs the pipeline.
      pipeline = "01jmq3hbakt5r0e136vd886hy9";
      # The owner's choice on 2026-10-17. On the frozen realistic set (48
      # spoken cases x 2 passes, workspace report
      # routing-realistic-retest-2026-10-16.md) Jev routed 96/96 correctly,
      # p50/p95 357/495 ms; Decisions 92/96 with one unsafe home route, p95
      # 4451 ms. On the earlier synthetic 100-case set Jev scored lower: 91/100
      # with 5 unsafe home routes against Decisions' 95/100 and 3, and it sent
      # 5 of 6 home+non-home mixes home (routing-100-benchmark-2026-10-16.md).
      provider = "jev";
      # the owner's OpenRouter key, encrypted to hoard_host as well
      openRouter.sopsFile = ../../secrets/openclaw/openrouter.yaml;
      # Diagnostic, not a speed fix: on 2026-10-16 23:01 two requests had no
      # Decisions answer within the default 4 s, and none logged an HTTP
      # response. Kept at 30 s for Jev until a new measurement or the owner
      # says otherwise: Jev's slowest benchmark call took 1.11 s, so the limit
      # only decides how long a hung request holds the user (the failure log
      # gives the elapsed ms). Each request is still one call, no retry, no
      # fallback.
      timeoutSeconds = 30;
    };

    settings = {
      live = {
        model = "gpt-live-1";
        voice = "marin";
        # Structured per https://developers.openai.com/api/docs/guides/live-prompting
        instructions = ''
          You are a voice assistant in a home, speaking through a small speaker.
          Speak warmly and naturally, in one or two short sentences. Never
          read out lists, IDs or markup.

          Pronunciation policy: Always pronounce Kyiv as Ukrainian Київ
          /ˈkɪjiu̯/, including when speaking English. Preserve the Ukrainian
          и vowel, ї glide and first-syllable stress.

          Backchannel policy: Use moderate backchannels. Acknowledge naturally
          without competing with the main response.

          Interruption policy: Stop speaking when the user interrupts. Listen to
          what they say.

          Delegation policy:
          Backend: the household's assistant. It reads and changes the home
          through Home Assistant (lights, climate, media, sensors and more),
          and has its own tools and memory beyond the home.

          Delegate to the backend when:
          - The user asks about the state of the home or asks to change it.
          - The user asks for something you cannot answer from the
            conversation: current information, something to remember or
            recall, or a task to carry out.
          - A correction changes the work already requested.
          - The user answers a question the backend asked, even with one word
            such as a room, yes or no. The backend asked it, so it decides.

          When the backend's result is a question, ask it and wait for the
          answer. Never answer it yourself or assume who is speaking.

          Do not delegate to the backend when:
          - You can answer from the conversation or a still-current result.
          - You need a brief clarification to understand the request.

          Delegate before giving an answer that depends on backend work.
          Do not guess the result while waiting.
        '';
      };
      openclaw = {
        instructions = ''
          This turn comes from a voice speaker in the home. Carry out the latest
          request in the conversation it quotes. Check the current state before
          changing something when the request is ambiguous, and before repeating
          an action an earlier, interrupted request may already have done. Your
          reply is spoken aloud: one or two short plain sentences with what you
          changed or found, and no IDs, lists or markup. The speaker hears this
          turn's reply alone, so end every turn with one: a yield ends it
          silently. When a subagent carries the work on, say so; its result
          reaches Telegram.
        '';
        # the voice starts with the Telegram conversation of the last day
        history = {
          # transcript rows, most of them tool calls and results
          max_messages = 300;
          max_age_s = 24 * 60 * 60;
          # stays within Live's 8,192-token history, Cyrillic included
          max_chars = 8000;
        };
      };
      idle_timeout_s = 8;
      max_conversation_s = 600;
    };
  };
}
