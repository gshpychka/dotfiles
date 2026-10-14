import {execFile} from 'node:child_process';
import {validate} from './core.mjs';
const SUDO='/run/wrappers/bin/sudo';
const HOST='@HOST@';
export function createTransport(invoke=(action,args,input,assertCurrent)=>new Promise((resolve,reject)=>{
  // No awaited work separates live host guard from fixed process admission.
  assertCurrent?.();
  const child=execFile(SUDO,['-n','--',HOST,action,...args],{
    encoding:'utf8',timeout:20000,maxBuffer:256*1024,
    env:{PATH:'@PATH@',HOME:process.env.HOME??'/var/lib/openclaw',LANG:'C.UTF-8'},
  },(error,stdout)=>{if(error)return reject(Error('NixOS host adapter refused or admission reply was lost; query the same requestId',{cause:error}));try{resolve(JSON.parse(stdout));}catch(error){reject(error);}});
  child.stdin.end(input??'');
})) {
 const id=x=>{if(typeof x!=='string'||x.length!==32||!/^[0-9a-f]{32}$/.test(x))throw Error('Invalid receipt id');return x;};
 return {
  async submit(p,route){validate(p);return invoke('submit',[],JSON.stringify({...p,agentId:route.agentId,sessionKey:route.sessionKey,delivery:route.delivery}),route.assertCurrent);},
  status(requestId,assertCurrent){return invoke('status',[id(requestId)],'',assertCurrent);},
  pendingCompletions(){return invoke('pending',[],'');},
  ackCompletion(requestId,receipt){return invoke('ack',[id(requestId)],JSON.stringify(receipt));},
 };
}
