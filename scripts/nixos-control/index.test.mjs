import assert from 'node:assert/strict';
import {test} from 'node:test';
import childProcess from 'node:child_process';
import {syncBuiltinESMExports} from 'node:module';
import fs from 'node:fs';
import plugin from './index.mjs';

test('installed SDK registration, owner guard and fixed argument-array dispatch', async () => {
  let factory, metadata, calls = [], current = true;
  plugin.register({registerTool(f, m) { factory = f; metadata = m; }});
  const manifest = JSON.parse(fs.readFileSync(new URL('./openclaw.plugin.json', import.meta.url)));
  assert.equal(plugin.id, manifest.id);
  assert.deepEqual(manifest.contracts.tools, [metadata.name]);
  assert.equal(factory.contextVersion, 2);
  assert.equal(metadata.optional, true);
  for (const context of [{}, {senderIsOwner: false}, {senderIsOwner: true},
    {senderIsOwner: true, sandboxed: true, assertInvocationCurrent() {}}]) {
    assert.equal(factory.create(context), null);
  }
  const tool = factory.create({senderIsOwner: true, assertInvocationCurrent() {
    if (!current) throw Error('revoked');
  }});
  assert.equal(tool.name, metadata.name);
  assert.deepEqual(tool.parameters.required, ['operation', 'revision']);
  assert.equal(tool.parameters.additionalProperties, false);
  const original = childProcess.execFile;
  childProcess.execFile = (...args) => {calls.push(args); args[3](null, '', 'Running as unit: nixos-control.service');};
  syncBuiltinESMExports();
  try {
    const revision = 'a'.repeat(40);
    const result = await tool.execute('call', {operation: 'build', revision});
    assert.match(result.content[0].text, /Submitted, not completed/);
    const [command, args, options] = calls[0];
    assert.equal(command, '/run/wrappers/bin/sudo');
    assert.deepEqual(args.slice(0, 2), ['-n', '--']);
    assert.match(args[2], /^(?:@HELPER@|\/nix\/store\/.*-nixos-control-start)$/);
    assert.deepEqual(args.slice(3), ['build', revision]);
    assert.equal(options.shell, undefined);
    current = false;
    await assert.rejects(tool.execute('call', {operation: 'switch', revision}), /revoked/);
    assert.equal(calls.length, 1);
    current = true;
    childProcess.execFile = (...args) => args[3](Error('failed'), '', 'refused');
    syncBuiltinESMExports();
    await assert.rejects(tool.execute('call', {operation: 'switch', revision}), /unknown.*refused/);
  } finally {
    childProcess.execFile = original;
    syncBuiltinESMExports();
  }
});
