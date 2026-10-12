# Voice: transcription of inbound audio, and spoken replies.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;
in
{
  options.my.openclaw = {
    transcription = lib.mkOption {
      type = lib.types.listOf (pkgs.formats.json { }).type;
      default = [ ];
      example = [
        {
          provider = "elevenlabs";
          model = "scribe_v2";
          capabilities = [ "audio" ];
        }
      ];
      description = "tools.media.models entries that transcribe inbound audio (https://docs.openclaw.ai/nodes/audio).";
    };

    tts = lib.mkOption {
      inherit (pkgs.formats.json { }) type;
      default = { };
      example = {
        provider = "elevenlabs";
        auto = "inbound";
      };
      description = "Text-to-speech settings (https://docs.openclaw.ai/tools/tts).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.openclaw-gateway.config = {
      tools.media = {
        # an empty model list otherwise falls through to auto-detection
        audio.enabled = cfg.transcription != [ ];
        models = cfg.transcription;
      };
      inherit (cfg) tts;
    };

    # OpenClaw decodes media with the ffmpeg and ffprobe in /run/current-system/sw/bin
    environment.systemPackages = [ pkgs.ffmpeg-headless ];
  };
}
