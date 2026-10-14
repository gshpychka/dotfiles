// Control adapter only: deployment belongs to the installed nixos-switch controller.
export const parameters = { type: 'object', additionalProperties: false,
  required: ['operation', 'revision', 'requestId'], properties: {
    operation: { enum: ['build', 'switch'] },
    revision: { type: 'string', minLength: 40, maxLength: 40, pattern: '^[0-9a-f]{40}$' },
    requestId: { type: 'string', minLength: 32, maxLength: 32, pattern: '^[0-9a-f]{32}$' } } };
export function validate(p) {
  if (!p || typeof p !== 'object' || Array.isArray(p) ||
      typeof p.operation !== 'string' || typeof p.revision !== 'string' || typeof p.requestId !== 'string' ||
      p.revision.length !== 40 || p.requestId.length !== 32 ||
      Object.keys(p).sort().join(',') !== 'operation,requestId,revision' ||
      !['build','switch'].includes(p.operation) || !/^[0-9a-f]{40}$/.test(p.revision) ||
      !/^[0-9a-f]{32}$/.test(p.requestId)) throw new Error('Invalid control request');
  return Object.freeze({ ...p });
}
// transport.submit must check assertCurrent at its final synchronous admission,
// not before awaiting preparation. It atomically persists intent and deduplicates
// requestId before starting an external unit. Unknown outcomes are never retried.
export function createControl(context, transport) {
  if (context.senderIsOwner !== true || typeof context.assertInvocationCurrent !== 'function' ||
      context.sandboxed || !context.agentId || !context.sessionKey) return null;
  return { name: 'nixos_control', label: 'NixOS Control',
    description: 'Build or switch hoard to a canonical-main commit; returns a durable operation receipt, not activation success.',
    parameters, executionMode: 'sequential',
    async execute(_callId, input) {
      const request = validate(input);
      const assertCurrent = () => {
        context.assertInvocationCurrent();
        if (context.senderIsOwner !== true) throw new Error('Owner authority required');
      };
      assertCurrent();
      const receipt = await transport.submit(request, {
        agentId: context.agentId, sessionKey: context.sessionKey, assertCurrent,
      });
      // Once accepted, preserve receipt even if authority subsequently expires.
      return { content: [{type:'text',text:JSON.stringify(receipt)}], details:{receipt} };
    } };
}
export function registerControl(api, transport) {
  api.registerTool({contextVersion:2, create:ctx => createControl(ctx,transport)},
    {name:'nixos_control', optional:true});
}
// Restart reconciliation: receipts remain in the controller outbox until the
// authenticated host event queue accepts them. No saved invocation/owner grant
// is reused. Delivery is informational and never initiates another deployment.
export async function reconcile(transport, emit) {
  for (const receipt of await transport.pendingCompletions({limit:32})) {
    if (await emit(receipt)) await transport.ackCompletion(receipt.requestId);
  }
}
