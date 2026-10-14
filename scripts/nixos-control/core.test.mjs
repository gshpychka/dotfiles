import test from 'node:test';
import assert from 'node:assert/strict';
import {createControl,registerControl,validate,validateDelivery} from './core.mjs';
const request={operation:'switch',revision:'a'.repeat(40),requestId:'b'.repeat(32)};
function owner(extra={}) {return {senderIsOwner:true,agentId:'main',sessionKey:'agent:main:main',deliveryContext:{channel:'telegram',to:'100000001'},assertInvocationCurrent(){},...extra};}
test('strict operations, immutable revision and id, no extra command/path fields',()=>{
  for(const p of [{...request,operation:'restart'},{...request,revision:'main'},
    {...request,revision:'a'.repeat(40)+';id'},{...request,requestId:'../x'},
    {...request,command:'id'},null]) assert.throws(()=>validate(p));
  assert.equal(validate({...request,operation:'build'}).operation,'build');
});
test('no identity, non-owner, sandbox and legacy contexts fail closed',()=>{
  for(const extra of [{senderIsOwner:false},{senderIsOwner:undefined},{sandboxed:true},
    {assertInvocationCurrent:undefined},{sessionKey:undefined}])
    assert.equal(createControl(owner(extra),{}),null);
});
test('v2 optional registration',()=>{
 let captured;registerControl({registerTool:(a,b)=>captured=[a,b]},{});
 assert.equal(captured[0].contextVersion,2);assert.equal(captured[1].optional,true);
});
test('revocation during awaited preparation blocks final-effect admission',async()=>{
 let current=true,effects=0;
 const tool=createControl(owner({assertInvocationCurrent(){if(!current)throw Error('revoked');}}),{
  async submit(p,c){await Promise.resolve();current=false;c.assertCurrent();effects++;}});
 await assert.rejects(tool.execute('call',request),/revoked/);assert.equal(effects,0);
});
test('internal accepted state remains owned after revocation; unknown transport error not replayed',async()=>{
 let current=true,calls=0;
 const tool=createControl(owner({assertInvocationCurrent(){assert.ok(current);}}),{
  async submit(p,c){calls++;c.assertCurrent();current=false;return {...p,phase:'accepted'};}});
 assert.equal((await tool.execute('call',request)).details.receipt.phase,'accepted');assert.equal(calls,1);
 const errorTool=createControl(owner(),{async submit(){calls++;throw Error('unknown');}});
 await assert.rejects(errorTool.execute('call',request),/unknown/);assert.equal(calls,2);
});
test('delivery is host context only; forged argument route or missing host route cannot admit effects',async()=>{
 let effects=0;const transport={async submit(p,route){effects++;assert.equal(route.delivery.to,'100000001');return {phase:'accepted'};}};
 await createControl(owner(),transport).execute('id',request);assert.equal(effects,1);
 await assert.rejects(createControl(owner(),transport).execute('id',{...request,delivery:{channel:'telegram',to:'attacker'}}));
 await assert.rejects(createControl(owner({deliveryContext:undefined}),transport).execute('id',request),/host-bound delivery route/);assert.equal(effects,1);
 for(const d of [{channel:'telegram\n',to:'x'},{channel:'telegram',to:'x\n'},{channel:'telegram',to:'x',command:'id'}])assert.throws(()=>validateDelivery(d));
});
