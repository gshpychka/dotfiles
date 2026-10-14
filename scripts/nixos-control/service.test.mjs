import test from 'node:test';import assert from 'node:assert/strict';import {registerCompletionService} from './service.mjs';
test('completion uses service lifetime, persists through drain/restart and only a joined ran wake acknowledges',async()=>{
 const pending=[{requestId:'b'.repeat(32),agentId:'main',sessionKey:'agent:main:main',phase:'completed'}];let service,tick,stopped=false,events=[],result={status:'skipped',reason:'draining'},acks=0;
 const api={registerService(s){service=s;},runtime:{system:{enqueueSystemEvent(text,route){events.push(route);return true;},async runHeartbeatOnce(){return result;}}}};
 const transport={async pendingCompletions(){return pending.slice();},async ackCompletion(){acks++;pending.shift();}};
 const ctx={scheduler:{signal:new AbortController().signal,schedule(p){tick=p.run;return{async stop(){stopped=true;}};}},logger:{error(){}},serviceHealth:{clearFailure(){},reportFailure(){}}};
 registerCompletionService(api,transport);assert.equal(service.apiVersion,2);await service.start(ctx);await tick();assert.equal(acks,0);
 await service.stop(ctx);assert.ok(stopped);await service.start(ctx);result={status:'ran'};await tick();assert.equal(acks,1);assert.equal(pending.length,0);
 assert.equal(events[0].sessionKey,'agent:main:main');assert.equal(events[0].contextKey,'nixos-control:'+'b'.repeat(32));
});
