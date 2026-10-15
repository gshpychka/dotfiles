import {execFile} from 'node:child_process';
import {definePluginEntry} from 'openclaw/plugin-sdk/plugin-entry';

export default definePluginEntry({
  id: 'nixos-control', name: 'NixOS Control',
  description: 'Owner-only shim for the existing nixos-switch controller.',
  register(api) {
    api.registerTool({contextVersion: 2, create(context) {
      if (context.senderIsOwner !== true || context.sandboxed ||
          typeof context.assertInvocationCurrent !== 'function') return null;
      return {
        name: 'nixos_control', label: 'NixOS Control', executionMode: 'sequential',
        description: 'Start a detached hoard build or switch. Admission is not completion; inspect journalctl -u nixos-control -u nixos-switch. Do not automatically retry an ambiguous admission.',
        parameters: {type: 'object', additionalProperties: false,
          required: ['operation', 'revision'], properties: {
            operation: {type: 'string', enum: ['build', 'switch']},
            revision: {type: 'string', pattern: '^[0-9a-f]{40}$'},
          }},
        execute(_id, {operation, revision}) {
          return new Promise((resolve, reject) => {
            // No awaited preparation between the host guard and fixed dispatch.
            context.assertInvocationCurrent();
            execFile('/run/wrappers/bin/sudo', ['-n', '--', '@HELPER@', operation, revision],
              {encoding: 'utf8', timeout: 20000, maxBuffer: 65536}, (error, stdout, stderr) => {
                if (error) return reject(new Error('Admission failed or unknown; inspect the journal before retrying. ' + stderr, {cause: error}));
                resolve({content: [{type: 'text', text: 'Submitted, not completed. ' + stdout + stderr + 'Follow: journalctl -u nixos-control -u nixos-switch --no-pager'}]});
              });
          });
        },
      };
    }}, {name: 'nixos_control', optional: true});
  },
});
