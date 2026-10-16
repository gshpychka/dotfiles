{ config, ... }:
{
  my.voice-broker = {
    enable = true;
    sopsFile = ../../secrets/hoard/voice-broker.yaml;
    recordings.enable = false;
    homeAssistant.url = "http://homeassistant.${config.my.domain}:8123";

    settings = {
      # EXPERIMENTAL comparison branch, not a production routing recommendation.
      routing = {
        strategy = "classifier";
        classifier = {
          # Endpoint verified, current account POST returns 403: capability-test branch.
          provider = "decisions";
          base_url = "https://api.openai.com/v1";
          model = "gpt-6-luna";
          timeout_s = 1.5;
          # Reuses existing openai-api-key systemd credential, never inline.
        };
        pipeline = "01jmq3hbakt5r0e136vd886hy9"; # Existing Remote, unchanged.
        devices = {
          room-assistant = "e96b17992356c46e2324bcdb0325cf13";
          kitchen-assistant = "1934b52923c293b268f3c9620e874156";
        };
        settle_s = 0.35;
      };
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
