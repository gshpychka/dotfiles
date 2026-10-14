// Uses the installed SDK, but only mock registrations; no service starts.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import plugin from './index.mjs';
const tools=[],services=[];
assert.equal(plugin.id,'nixos-control');
plugin.register({registerTool(factory,metadata){tools.push({factory,metadata});},registerService(service){services.push(service);}});
const manifest=JSON.parse(fs.readFileSync(new URL('./openclaw.plugin.json',import.meta.url),'utf8'));
assert.deepEqual(tools.map(t=>t.metadata.name),manifest.contracts.tools);
for(const t of tools){assert.equal(t.factory.contextVersion,2);assert.equal(t.metadata.optional,true);assert.equal(t.factory.create({senderIsOwner:false}),null);assert.equal(t.factory.create({senderIsOwner:true}),null);
 const tool=t.factory.create({senderIsOwner:true,assertInvocationCurrent(){throw Error('closed');},agentId:'main',sessionKey:'agent:main:main'});
 assert.ok(tool);assert.equal(tool.name,t.metadata.name);assert.equal(tool.parameters.additionalProperties,false);
 if(tool.name==='nixos_control')await assert.rejects(tool.execute('id',{operation:'switch',revision:'a'.repeat(40),requestId:'b'.repeat(32)}),/closed/);
}
assert.equal(services.length,1);assert.equal(services[0].apiVersion,2);
console.log('Installed SDK owner-v2 registration and manifest smoke check passed; no real host action or service start.');
