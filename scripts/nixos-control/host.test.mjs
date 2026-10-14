import test from 'node:test';import assert from 'node:assert/strict';
import fs from 'node:fs';import os from 'node:os';import path from 'node:path';import {EventEmitter} from 'node:events';
import {createHost,main,atomic} from './host.mjs';import {createTransport} from './transport.mjs';
const p={operation:'switch',revision:'a'.repeat(40),requestId:'b'.repeat(32),agentId:'main',sessionKey:'agent:main:main',delivery:{channel:'telegram',to:'100000001'}};
function fixture(t,{exitCode=0,signal=null,log='',admitFail=false}={}){
 const state=fs.mkdtempSync(path.join(os.tmpdir(),'nixos-control-test-'));t.after(()=>fs.rmSync(state,{recursive:true,force:true}));
 let active=false,activating=false,calls=[],launched=[];
 const run=(cmd,args)=>{calls.push([cmd,args]);if(args[0]==='show')return (args[1]==='nixos-switch.service'?activating:active)?'active\n':'inactive\n';if(admitFail)throw Error('lost');active=true;return '';};
 const launch=(cmd,args,options)=>{launched.push([cmd,args]);fs.writeSync(options.stdio[1],log);const child=new EventEmitter();queueMicrotask(()=>child.emit('exit',exitCode,signal));return child;};
 const make=()=>createHost({state,run,launch,controller:'/nix/store/fixed-controller/bin/nixos-switch'});
 return {state,make,calls,launched,setActive(v){active=v;},setActivating(v){activating=v;}};
}
test('durable intent before external admission, exact id dedupe and conflicting replay denied',t=>{
 const f=fixture(t),h=f.make();assert.equal(h.submit(p).phase,'accepted');
 assert.ok(fs.existsSync(path.join(f.state,p.requestId+'.json')));
 assert.equal(h.submit(p).phase,'accepted');assert.equal(f.calls.filter(c=>c[1][0]!=='show').length,1);
 assert.throws(()=>h.submit({...p,revision:'c'.repeat(40)}),/conflicts/);
 assert.throws(()=>h.submit({...p,sessionKey:'agent:main:other'}),/conflicts/);
 assert.throws(()=>h.submit({...p,delivery:{channel:'telegram',to:'different'}}),/conflicts/);
});
test('busy runner or existing activation blocks second controller without receipt',t=>{
 const f=fixture(t);f.setActivating(true);const h=f.make();assert.throws(()=>h.submit(p),/busy/);
 assert.equal(fs.readdirSync(f.state).length,0);f.setActivating(false);h.submit(p);
 assert.throws(()=>h.submit({...p,requestId:'c'.repeat(32)}),/busy/);
});
test('mocked controller only receives fixed executable and operation/revision; terminal receipt survives reopening',async t=>{
 const f=fixture(t),h=f.make();h.submit(p);await h.worker(p.requestId);f.setActive(false);
 assert.deepEqual(f.launched,[['/nix/store/fixed-controller/bin/nixos-switch',['switch',p.revision]]]);
 const reopened=f.make();assert.equal(reopened.status(p.requestId).phase,'completed');
 assert.equal(reopened.pending().length,1);assert.throws(()=>reopened.ack(p.requestId),/platform receipt/);
 assert.throws(()=>reopened.ack(p.requestId,{channel:'discord',messageId:'12'}),/matching/);
 reopened.ack(p.requestId,{channel:'telegram',messageId:'12'});assert.equal(f.make().pending().length,0);
 await assert.rejects(reopened.worker(p.requestId),/replay/);
});
test('build uses same controller without switch; rollback evidence and incomplete outcomes retained',async t=>{
 for(const scenario of [{exitCode:0,operation:'build',phase:'completed'},
 {exitCode:1,log:'returned to generation 348 and /nix/store/prior\n',phase:'failed',rollback:true},
 {exitCode:1,log:'build failed',phase:'failed',rollback:false},
 {exitCode:2,log:'rollback incomplete: a step above failed',phase:'rollback-incomplete'},
 {exitCode:null,signal:'SIGTERM',phase:'interrupted'}]){
  const f=fixture(t,scenario),h=f.make();h.submit({...p,operation:scenario.operation??'switch'});
  const r=await h.worker(p.requestId);assert.equal(r.phase,scenario.phase);
  if(scenario.rollback!==undefined)assert.equal(r.rollbackConfirmed,scenario.rollback);
 }
});
test('lost admission/reboot marks unknown without replay; same id cannot dispatch again',t=>{
 const f=fixture(t,{admitFail:true}),h=f.make();assert.throws(()=>h.submit(p),/reply failed/);
 assert.equal(h.status(p.requestId).phase,'interrupted');h.submit(p);assert.equal(f.calls.filter(c=>c[1][0]!=='show').length,1);
});
test('receipt tamper ids, shell parameters and extra transport fields rejected before systemd',async t=>{
 const f=fixture(t),h=f.make();
 for(const r of [{...p,revision:'a'.repeat(40)+';id'},{...p,requestId:'../../etc/passwd'},
 {...p,operation:'switch;id'},{...p,command:'id'},{...p,agentId:'root;id'},
 {...p,revision:p.revision+'\n'},{...p,requestId:p.requestId+'\n'},{...p,agentId:'main\n'}])assert.throws(()=>h.submit(r));
 for(const id of ['../x','b'.repeat(32)+';id','b'.repeat(32)+'\n',{},null])assert.throws(()=>h.status(id));
 assert.equal(f.calls.length,0);
 await assert.rejects(main(['submit'],JSON.stringify(p),{host:h,uid:1000,sudoUser:'openclaw'}),/Root/);
 await assert.rejects(main(['submit'],JSON.stringify(p),{host:h,uid:0,sudoUser:'stranger'}),/identity/);
 await assert.rejects(main(['worker',p.requestId],'',{host:h,uid:0,sudoUser:'openclaw'}),/systemd-owned/);
});
test('transport forwards no caller executable/path/environment; closure prevents dispatch',async()=>{
 let calls=0,captured;const transport=createTransport((action,args,input,guard)=>{guard?.();calls++;captured={action,args,p:JSON.parse(input)};return Promise.resolve({phase:'accepted'});});
 const q={operation:p.operation,revision:p.revision,requestId:p.requestId};
 await transport.submit(q,{agentId:'main',sessionKey:'agent:main:main',delivery:p.delivery,assertCurrent(){}});
 assert.equal(captured.action,'submit');assert.deepEqual(captured.args,[]);assert.deepEqual(captured.p,p);
 await assert.rejects(transport.submit(q,{assertCurrent(){throw Error('drain closed');}}),/drain closed/);assert.equal(calls,1);
});

test('durable pending cursor fairly rotates more than 32 failed receipts across restarts',t=>{
 const f=fixture(t);const ids=Array.from({length:70},(_,i)=>(i+1).toString(16).padStart(32,'0'));
 for(const requestId of ids)atomic(path.join(f.state,requestId+'.json'),{...p,requestId,phase:'completed',completionAcknowledged:false});
 const batches=[f.make().pending(),f.make().pending(),f.make().pending()];
 assert.ok(batches.every(b=>b.length===32));assert.equal(new Set(batches.flat().map(r=>r.requestId)).size,70);
 assert.equal(fs.statSync(path.join(f.state,'completion-cursor.json')).mode&0o777,0o600);
 assert.ok(ids.every(id=>f.make().status(id).completionAcknowledged===false));
});
