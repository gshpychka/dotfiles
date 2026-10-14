// Uses the installed SDK, but only mock registrations; no service starts.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {fileURLToPath} from 'node:url';
import {createControl} from './core.mjs';
import plugin from './index.mjs';
const tools=[],services=[];
assert.equal(plugin.id,'nixos-control');
plugin.register({registerTool(factory,metadata){tools.push({factory,metadata});},registerService(service){services.push(service);}});
const manifest=JSON.parse(fs.readFileSync(new URL('./openclaw.plugin.json',import.meta.url),'utf8'));
assert.deepEqual(tools.map(t=>t.metadata.name),manifest.contracts.tools);
for(const t of tools){assert.equal(t.factory.contextVersion,2);assert.equal(t.metadata.optional,true);assert.equal(t.factory.create({senderIsOwner:false}),null);assert.equal(t.factory.create({senderIsOwner:true}),null);
 const tool=t.factory.create({senderIsOwner:true,assertInvocationCurrent(){throw Error('closed');},agentId:'main',sessionKey:'agent:main:main',deliveryContext:{channel:'telegram',to:'100000001'}});
 assert.ok(tool);assert.equal(tool.name,t.metadata.name);assert.equal(tool.parameters.additionalProperties,false);
 if(tool.name==='nixos_control')await assert.rejects(tool.execute('id',{operation:'switch',revision:'a'.repeat(40),requestId:'b'.repeat(32)}),/closed/);
}
assert.equal(services.length,1);assert.equal(services[0].apiVersion,2);
// Execute the exact installed host callback binder body with mock lifecycle/scope
// dependencies, not a hand-written approximation. Production never imports chunks.
const sdkDist=path.resolve(path.dirname(fileURLToPath(import.meta.resolve('openclaw/plugin-sdk/plugin-entry'))),'..');
const chunk=fs.readdirSync(sdkDist).filter(n=>/^tools-.*\.mjs$/.test(n)).map(n=>fs.readFileSync(path.join(sdkDist,n),'utf8')).find(s=>s.includes('function bindPluginToolCallbacks('));
assert.ok(chunk,'Installed SDK callback binder source is required for this pinned-host regression');
const start=chunk.indexOf('function bindPluginToolCallbacks('),end=chunk.indexOf('function createPluginToolFactoryResolver(',start);
assert.ok(end>start);
const bind=vm.runInNewContext('('+chunk.slice(start,end).trim()+'\n)',{
 capturePluginLifecycleAuthority:()=>()=>true,
 isPromiseLike:x=>x&&typeof x.then==='function',
 runWithPluginToolScope:(_entry,_registry,run)=>run(),
 runWithTrackedCancellation:(_signal,run)=>run(_signal),copyPluginToolMeta(){},
});
let current=true;const durable=new Map();
const guard=()=>{if(!current)throw Error('authority revoked');};
const req={operation:'build',revision:'a'.repeat(40),requestId:'c'.repeat(32)};
const inner=createControl({senderIsOwner:true,agentId:'main',sessionKey:'agent:main:main',deliveryContext:{channel:'telegram',to:'100000001'},assertInvocationCurrent:guard},{
 async submit(p,route){route.assertCurrent();durable.set(p.requestId,{...p,phase:'accepted'});current=false;return durable.get(p.requestId);}
});
const bound=bind({pluginId:'nixos-control'},{plugins:[{id:'nixos-control'}]},inner,guard);
await assert.rejects(bound.execute('call',req),/authority revoked/);
assert.equal(durable.get(req.requestId).phase,'accepted');assert.equal(durable.size,1);
console.log('Installed SDK v2 registration, manifest and actual post-return callback revocation regression passed; host effects mocked.');
