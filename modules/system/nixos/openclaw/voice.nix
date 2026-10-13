# Voice: transcription of inbound audio, and spoken replies.
{ config, lib, ... }:
let
  cfg = config.my.openclaw;
in
{
  options.my.openclaw = {
    transcription = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.json);
      default = [ ];
      example = [
        {
          provider = "elevenlabs";
          model = "scribe_v2";
        }
      ];
      description = "Models that transcribe inbound audio, tried in order, as tools.media.models entries (https://docs.openclaw.ai/nodes/audio); an empty list leaves audio untranscribed.";
    };

    tts = lib.mkOption {
      type = lib.types.attrsOf lib.types.json;
      default = { };
      example = {
        provider = "elevenlabs";
        auto = "inbound";
      };
      description = "OpenClaw's tts config: when and how replies are spoken (https://docs.openclaw.ai/tools/tts).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.openclaw-gateway.config = {
      tools.media = {
        # OpenClaw auto-detects a transcriber for an empty model list
        audio.enabled = cfg.transcription != [ ];
        # an untagged entry serves every media capability its provider has
        models = map (entry: entry // { capabilities = [ "audio" ]; }) cfg.transcription;
      };
      inherit (cfg) tts;
    };
  };
}
