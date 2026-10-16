{ config, lib, ... }:
let
  # my.openclaw.mcpServers' names: OpenClaw names an MCP tool <server>__<tool>
  # (src/agents/agent-bundle-mcp-names.ts), and Home Assistant's MCP server
  # names its tools <integration>__<tool>.
  homeAssistantMcp = "home-assistant";
  homeAssistantAdminMcp = "home-assistant-admin";

  parallel = config.my.voice-broker.mode == "parallel";

  # Structured per https://developers.openai.com/api/docs/guides/live-prompting.
  # Who the voice is, in either mode.
  liveCommon = ''
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

  '';
  # Gated: the backend (OpenClaw's main agent) also acts on the home, when the classifier sends it there.
  liveGated = ''
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
  # Parallel: Home Assistant alone acts on the home, and the backend (the voice agent) can't.
  liveParallel = ''
    Home policy:
    Home Assistant hears everything said here, on its own, and alone
    carries out requests about the home: lights, climate, media, scenes,
    sensors and the state of devices. Its results reach you as context
    starting "Home Assistant:". Say them in your own words.
    - Never say a home request is done, or what a device is doing,
      before Home Assistant's result says so. If it says nothing was
      done, or that it may have acted, say exactly that.
    - When Home Assistant asks a question, ask the user and wait. Their
      answer reaches Home Assistant by itself.
    - A correction of a home request goes to Home Assistant the same
      way: let the user say it.

    Delegation policy:
    Backend: the household's assistant, with its own tools and memory
    beyond the home. It cannot change anything in the home.

    Delegate to the backend when:
    - The user asks for something you cannot answer from the
      conversation, and it is not home control: current information,
      something to remember or recall, or a task to carry out.
    - A correction changes the work already requested of the backend.
    - The user answers a question the backend asked, even with one word.

    When a request mixes home control with other work, delegate it:
    Home Assistant does the home part, the backend the rest, and you
    get both results together. Tell them as one answer.

    When the backend's result is a question, ask it and wait for the
    answer. Never answer it yourself or assume who is speaking.

    Do not delegate to the backend when:
    - The request is only home control: Home Assistant has it.
    - You can answer from the conversation or a still-current result.
    - You need a brief clarification to understand the request.

    Delegate before giving an answer that depends on backend work.
    Do not guess the result while waiting.
  '';
  openclawGated = ''
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
  openclawParallel = ''
    This turn comes from a voice speaker in the home. Carry out the latest
    request in the conversation it quotes, except home control: Home
    Assistant hears the same speech and alone changes the home, and you
    cannot. Never say a home change was made; when the request is only
    about the home, say in a few words that Home Assistant has it. You may
    read the home's state to answer a question. Your reply is spoken
    aloud: one or two short plain sentences with what you found or did,
    and no IDs, lists or markup. The speaker hears this turn's reply
    alone, so end every turn with one: a yield ends it silently.
  '';
in
{
  assertions = [
    {
      assertion = lib.all (server: config.my.openclaw.mcpServers ? ${server}) [
        homeAssistantMcp
        homeAssistantAdminMcp
      ];
      message = "machines/hoard/voice-broker.nix names the voice agent's tools after MCP servers that no longer exist.";
    }
  ];

  my.voice-broker = {
    enable = true;
    sopsFile = ../../secrets/hoard/voice-broker.yaml;
    recordings.enable = false;
    homeAssistant.url = "http://homeassistant.${config.my.domain}:8123";

    # Gated, with Jev, until parallel mode's prerequisites are in place: Home
    # Assistant's home-only agent and "Voice broker home" pipeline
    # (scripts/voice-pe/runbook.md), and the gateway owner's check of the voice
    # agent's tool policy (workspace report parallel-ha-audio-production-2026-10-17.md).
    # Switching is this line alone: "parallel".
    mode = "gated";
    # the owner's OpenRouter key, encrypted to hoard_host as well
    openRouter.sopsFile = ../../secrets/openclaw/openrouter.yaml;

    routing = {
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
      # Diagnostic, not a speed fix: on 2026-10-16 23:01 two requests had no
      # Decisions answer within the default 4 s, and none logged an HTTP
      # response. Kept at 30 s for Jev until a new measurement or the owner
      # says otherwise: Jev's slowest benchmark call took 1.11 s, so the limit
      # only decides how long a hung request holds the user (the failure log
      # gives the elapsed ms). Each request is still one call, no retry, no
      # fallback.
      timeoutSeconds = 30;
    };

    homeAssistant = {
      # Parallel mode. Created by voice-broker-ha-setup (scripts/voice-pe/runbook.md): "Remote"'s
      # speech recognition, stt.groq in English, unchanged, with a dedicated
      # home-only OpenAI conversation agent. "Remote"'s own agent,
      # conversation.chatgpt, answers general questions by its prompt, so it
      # would overlap the agent. The Voice PEs' own pipeline selects don't
      # apply: the broker, not the satellite, runs the pipeline.
      pipeline = "Voice broker home";
      # Exposed to Assist as of 2026-10-17 (homeassistant/expose_entity/list), and not about
      # the home: ask_gpt hands the question to another LLM agent, the other is a weather
      # forecast. Exposure is per assistant, not per agent, so the home-only agent sees them too.
      nonHomeTools = [
        "ask_gpt"
        "voice_weather_forecasts_full_llm_script"
      ];
    };

    agent = {
      # Home Assistant's MCP tools that only read (their readOnlyHint, tools/list on 2026-10-17)
      allow = [
        "${homeAssistantMcp}__homeassistant__GetLiveContext"
        "${homeAssistantMcp}__llm__GetDateTime"
      ];
      # The admin server can change anything in Home Assistant; "*" keeps it from even being listed.
      deny = [ "${homeAssistantAdminMcp}__*" ];
    };

    # Checks each Home Assistant action, read-only, through the voice agent.
    observer.enable = parallel;

    settings = {
      live = {
        model = "gpt-live-1";
        voice = "marin";
        instructions = liveCommon + (if parallel then liveParallel else liveGated);
      };
      openclaw = {
        instructions = if parallel then openclawParallel else openclawGated;
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
