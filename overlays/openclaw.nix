# OpenClaw from github:gshpychka/nix-openclaw, built on its pinned source with
# the patches in ./openclaw applied.
inputs: _final: prev:
let
  inherit (prev.stdenv.hostPlatform) system;
  # the nixpkgs that builds the rest of the gateway; updates to ours leave it unchanged
  openclawPkgs = inputs.nix-openclaw.inputs.nixpkgs.legacyPackages.${system};
in
{
  openclaw = inputs.nix-openclaw.packages.${system}.openclaw-gateway.override (old: {
    gatewaySrc = openclawPkgs.applyPatches {
      name = "openclaw-${old.sourceInfo.releaseVersion}-source";
      src = openclawPkgs.fetchFromGitHub {
        inherit (old.sourceInfo)
          owner
          repo
          rev
          hash
          ;
      };
      patches = [
        # questions asked after delegated work finishes accept answers from the chat that started it
        ./openclaw/delegated-completion-question-caller.patch
        # the turn that reports a finished subagent can ask questions at all
        ./openclaw/completion-turn-question-scope.patch
        # a question asked from code mode keeps the turn open until it is answered
        ./openclaw/code-mode-question-wait.patch
        # the turn that reports a finished subagent shows its questions in the chat
        ./openclaw/delivered-run-question-prompts.patch
        # a Claude Code session belongs to the agent that starts it, so the gateway accepts it
        ./openclaw/acp-raw-harness-owner.patch
        # a turn carries on after its question is answered by typing
        ./openclaw/question-answer-worker-append.patch
      ];
    };
    # follows the source's pnpm-lock.yaml
    pnpmDepsHash = "sha256-CO2ykEZhdyCVCgQQlNyFZl274VfGzgNl7TbJ6/gMRp8=";
  });
}
