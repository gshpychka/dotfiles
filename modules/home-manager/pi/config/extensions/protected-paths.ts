import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// sops keeps everything under a secrets/ tree encrypted at rest, and a tool write emits plaintext.
const secretPaths = [/(^|\/)secrets\//, /(^|\/)\.env(\.[^/]+)?$/];

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "write" && event.toolName !== "edit") {
      return undefined;
    }

    const path = event.input.path as string;
    if (!secretPaths.some((p) => p.test(path))) {
      return undefined;
    }

    if (ctx.hasUI) {
      ctx.ui.notify(`Blocked ${event.toolName} to ${path}`, "warning");
    }
    return { block: true, reason: `${path} is encrypted; edit it with sops` };
  });
}
