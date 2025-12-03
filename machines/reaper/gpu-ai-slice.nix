# common systemd slice for GPU-intensive AI services
{ config, ... }:
{
  systemd.slices.gpu-ai = {
    description = "GPU-intensive AI services";
  };

  systemd.services = {
    # TODO: would it be better to do this in the services themselves?
    ollama.serviceConfig.Slice = config.systemd.slices.gpu-ai.name;
    "wyoming-faster-whisper-hass".serviceConfig.Slice = config.systemd.slices.gpu-ai.name;
    "docker-kokoro-fastapi".serviceConfig.Slice = config.systemd.slices.gpu-ai.name;
  };
}
