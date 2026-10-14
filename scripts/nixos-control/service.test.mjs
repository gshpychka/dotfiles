import test from 'node:test';import assert from 'node:assert/strict';import {registerCompletionService} from './service.mjs';
const receipt={requestId:'b'.repeat(32),agentId:'main',sessionKey:'agent:main:main',operation:'switch',revision:'a'.repeat(40),delivery:{channel:'telegram',to:'100000001',threadId:123},phase:'completed'};
function fixture(){
 const pending=[{...receipt}];let service,tick,stopped=false,acks=[],sends=[],mode='offline';const abort=new AbortController();
 const api={
  registerService(s){service=s;},
  runtime:{
   config:{current(){return {channels:{telegram:{enabled:mode!=='disabled'}},agents:{defaults:{heartbeat:{every:'0m'}}}};}},
   channel:{outbound:{async loadAdapter(channel){
    assert.equal(channel,'telegram');
    return {async sendText(p){
     if(mode==='close-during-preparation')abort.abort();
     p.assertDirectAdapterHandoff();sends.push(p);
     if(mode==='offline')throw Error('offline');
     if(mode==='suppressed')return {channel,messageId:'12',outcome:'suppressed'};
     return {channel,messageId:'12',outcome:'sent'};
    }};
   }}}
  }
 };
 const transport={async pendingCompletions(){return pending.slice();},async ackCompletion(id,r){acks.push([id,r]);pending.shift();}};
 const ctx={scheduler:{signal:abort.signal,schedule(p){tick=p.run;return{async stop(){stopped=true;}};}},logger:{error(){}},serviceHealth:{clearFailure(){},reportFailure(){}}};
 registerCompletionService(api,transport);
 return {service,ctx,pending,acks,sends,mode(m){mode=m;},tick(){return tick();},stopped(){return stopped;}};
}
test('restart outbox sends exact captured route despite 0m heartbeat; platform receipt alone acknowledges',async()=>{
 const f=fixture();assert.equal(f.service.apiVersion,2);await f.service.start(f.ctx);await f.tick();assert.equal(f.acks.length,0);assert.equal(f.pending.length,1);
 await f.service.stop(f.ctx);assert.ok(f.stopped());await f.service.start(f.ctx);f.mode('sent');await f.tick();assert.equal(f.acks.length,1);assert.equal(f.pending.length,0);
 assert.equal(f.sends[0].to,receipt.delivery.to);assert.equal(f.sends[0].threadId,123);assert.deepEqual(f.acks[0],[receipt.requestId,{channel:'telegram',messageId:'12'}]);
});
test('suppressed send and revoked/disabled channel retain durable outbox, never claim delivery',async()=>{
 for(const mode of ['suppressed','disabled','close-during-preparation']){const f=fixture();await f.service.start(f.ctx);f.mode(mode);await f.tick();assert.equal(f.acks.length,0);assert.equal(f.pending.length,1);}
});

test('failed first route cannot starve healthy receipts; aggregate failure retained',async()=>{
 let service,tick;const sends=[],acks=[],failures=[];
 const abort=new AbortController();
 const api={registerService(s){service=s;},runtime:{config:{current:()=>({channels:{telegram:{enabled:true}}})},channel:{outbound:{async loadAdapter(){return {async sendText(p){p.assertDirectAdapterHandoff();sends.push(p.to);if(p.to==='offline')throw Error('offline');return {channel:'telegram',messageId:'ok'};}};}}}}};
 const pending=[{...receipt,delivery:{channel:'telegram',to:'offline'}},{...receipt,requestId:'c'.repeat(32),delivery:{channel:'telegram',to:'healthy'}}];
 registerCompletionService(api,{pendingCompletions:async()=>pending,ackCompletion:async(id)=>acks.push(id)});
 await service.start({scheduler:{signal:abort.signal,schedule(p){tick=p.run;return {stop:async()=>{}};}},serviceHealth:{clearFailure(){assert.fail('must report aggregate failure');},reportFailure(e){failures.push(e);}},logger:{error(){}}});
 await tick();assert.deepEqual(sends,['offline','healthy']);assert.deepEqual(acks,['c'.repeat(32)]);assert.equal(failures[0].errors.length,1);
 abort.abort();await tick();assert.equal(sends.length,2);
});
