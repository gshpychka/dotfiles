inputs: [
  (import ./llm-agents.nix inputs)
  (_final: prev: import ../packages { pkgs = prev; })
  (import ./pam-ssh-agent-auth.nix)
  inputs.mcp-servers-nix.overlays.default
]
