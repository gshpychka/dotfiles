{ config, ... }:
{
  my.realtime-voice = {
    enable = true;
    sopsFile = ../../secrets/hoard/realtime-voice.yaml;
    recordings.enable = true;
    # HA's built-in MCP Server integration: the Assist API over exposed entities
    mcpServers.home = {
      url = "http://homeassistant.${config.my.domain}:8123/api/mcp";
      bearerTokenKey = "ha-token";
    };

    settings = {
      # Each conversation runs on one of these two backends.
      realtime = {
        model = "gpt-realtime-2.1";
        voice = "marin";
        instructions = ''
          You are a voice assistant in a home, speaking through a small speaker.
          Keep answers short and conversational; never read out lists,
          IDs or markup. You can control and inspect the home through the home__
          tools. Confirm out loud what you changed. If you are interrupted, stop
          and listen.
        '';
        turn_eagerness = "high";
        transcription_model = "gpt-transcribe";
        barge_in = {
          vad_threshold = 0.6;
          min_speech_ms = 192;
          min_level_dbfs = -45;
          preroll_ms = 400;
        };
      };
      live = {
        model = "gpt-live-1";
        voice = "marin";
        # Structured per https://developers.openai.com/api/docs/guides/live-prompting
        instructions = ''
          You are a voice assistant in a home, speaking through a small speaker.
          Speak warmly and naturally, in one or two short sentences. Never
          read out lists, IDs or markup.

          Backchannel policy: Use moderate backchannels. Acknowledge naturally
          without competing with the main response.

          Interruption policy: Stop speaking when the user interrupts. Listen to
          what they say.

          Delegation policy:
          Backend tools:
          - Home control: read and change lights, climate, media, sensors and
            anything else exposed in Home Assistant, and run its voice scripts.

          Delegate to the backend when:
          - The user asks about the state of the home or asks to change it.
          - A correction changes the work already requested.

          Do not delegate to the backend when:
          - You can answer from the conversation or a still-current result.
          - You need a brief clarification to understand the request.

          Delegate before giving an answer that depends on backend work.
          Do not guess the result while waiting.
        '';
        delegation = {
          model = "gpt-6-luna";
          instructions = ''
            You carry out requests for a voice assistant in one home. Use
            the home__ tools to inspect and control the home. Check the current state before changing something when the request is
            ambiguous. Report the outcome in one short plain sentence that can be
            spoken aloud: what you changed or found, with no IDs, lists or markup.
          '';
          reasoning_effort = "none";
        };
      };
      idle_timeout_s = 8;
      max_conversation_s = 600;
    };
  };
}
