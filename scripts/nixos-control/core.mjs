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
export function validateDelivery(d) {
  if (!d || typeof d !== 'object' || Array.isArray(d) ||
      Object.keys(d).some(k=>!['channel','to','accountId','threadId'].includes(k)) ||
      typeof d.channel !== 'string' || !/^[a-z][a-z0-9-]{0,31}$/.test(d.channel) || /[\r\n\0]/.test(d.channel) ||
      typeof d.to !== 'string' || !d.to.length || d.to.length>512 || /[\r\n\0]/.test(d.to) ||
      (d.accountId !== undefined && (typeof d.accountId !== 'string' || !d.accountId.length || d.accountId.length>128 || /[\r\n\0]/.test(d.accountId))) ||
      (d.threadId !== undefined && !((typeof d.threadId === 'string' && d.threadId.length>0 && d.threadId.length<=128 && !/[\r\n\0]/.test(d.threadId)) || (Number.isSafeInteger(d.threadId) && d.threadId>=0)))) throw Error('No valid host-bound completion route');
  return Object.freeze({...d});
}
export function captureDelivery(context) {
  const d=context.deliveryContext;
  if (!d) throw Error('Invoke NixOS control from an owner conversation with a host-bound delivery route');
  return validateDelivery({channel:d.channel,to:d.to,
    ...(d.accountId!=null?{accountId:d.accountId}:{}),...(d.threadId!=null?{threadId:d.threadId}:{})});
}
export function createControl(context, transport) {
  if (context.senderIsOwner !== true || typeof context.assertInvocationCurrent !== 'function' ||
      context.sandboxed || !context.agentId || !context.sessionKey) return null;
  return { name: 'nixos_control', label: 'NixOS Control',
    description: 'Build or switch hoard to a canonical-main commit; returns a durable operation receipt, not activation success.',
    parameters, executionMode: 'sequential',
    async execute(_callId, input) {
      const request = validate(input);
      const delivery = captureDelivery(context);
      const assertCurrent = () => {
        context.assertInvocationCurrent();
        if (context.senderIsOwner !== true) throw new Error('Owner authority required');
      };
      assertCurrent();
      const receipt = await transport.submit(request, {
        agentId: context.agentId, sessionKey: context.sessionKey, delivery, assertCurrent,
      });
      // Preserve accepted state; the SDK post-return guard may still reject this
      // reply. Caller knows requestId and must query it, never retry with a new id.
      return { content: [{type:'text',text:JSON.stringify(receipt)}], details:{receipt} };
    } };
}
export function registerControl(api, transport) {
  api.registerTool({contextVersion:2, create:ctx => createControl(ctx,transport)},
    {name:'nixos_control', optional:true});
}
