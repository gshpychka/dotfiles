import fs from 'node:fs';
import path from 'node:path';
import {execFileSync, spawn} from 'node:child_process';
import {validate,validateDelivery} from './core.mjs';
// Packaging substitutes these constants; no request or plugin config controls them.
export const STATE = '@STATE@';
export const CONTROLLER = '@CONTROLLER@';
const SYSTEMD_RUN = '@SYSTEMD_RUN@';
const SYSTEMCTL = '@SYSTEMCTL@';
const UNIT = 'nixos-control-receipt';
export const terminal = r => ['completed','failed','interrupted','rollback-incomplete'].includes(r.phase);
export function atomic(file,value) {
  const temp=file+'.tmp-'+process.pid;
  const fd=fs.openSync(temp,'wx',0o600);
  try { fs.writeFileSync(fd,JSON.stringify(value)+'\n');fs.fsyncSync(fd); } finally {fs.closeSync(fd);}
  fs.renameSync(temp,file);
  const dir=fs.openSync(path.dirname(file),'r');try{fs.fsyncSync(dir);}finally{fs.closeSync(dir);}
}
export function createHost({state=STATE,controller=CONTROLLER,run=execFileSync,workerFile=import.meta.filename,node=process.execPath,launch=spawn}={}) {
  const file=id=>{if(typeof id!=='string'||id.length!==32||!/^[0-9a-f]{32}$/.test(id))throw Error('Invalid request id');return path.join(state,id+'.json');};
  const read=id=>JSON.parse(fs.readFileSync(file(id),'utf8'));
  const running=()=>{
    try {return [UNIT,'nixos-switch'].some(unit=>{const v=run(SYSTEMCTL,['show',unit+'.service','--property=ActiveState','--value'],{encoding:'utf8',timeout:5000}).trim();return ['active','activating','deactivating','reloading'].includes(v);});}
    catch {throw Error('Unable to establish controller unit state');}
  };
  const readReconciled=id=>{
    const r=read(id);
    if(!terminal(r) && !running()) {r.phase='interrupted';r.finishedAt=new Date().toISOString();r.note='Receipt runner absent; outcome unknown. Never replay automatically.';atomic(file(id),r);}
    return r;
  };
  return {
    submit(input) {
      if(!input||Object.keys(input).sort().join(',')!=='agentId,delivery,operation,requestId,revision,sessionKey')throw Error('Invalid submission');
      const {agentId,sessionKey,delivery,...p}=input;validate(p);validateDelivery(delivery);
      if(typeof agentId!=='string'||(!/^[a-zA-Z0-9_-]{1,64}$/.test(agentId)||/[\r\n]/.test(agentId))||typeof sessionKey!=='string'||sessionKey.length>512||!sessionKey.startsWith('agent:'+agentId+':')||/[\r\n\0]/.test(sessionKey))throw Error('Invalid host route');
      fs.mkdirSync(state,{recursive:true,mode:0o700});
      if(fs.existsSync(file(p.requestId))){const r=readReconciled(p.requestId);for(const k of ['operation','revision','agentId','sessionKey','delivery'])if(JSON.stringify(r[k])!==JSON.stringify(input[k]))throw Error('Request id replay conflicts with admitted payload');return r;}
      if(running())throw Error('Controller busy; no new intent admitted');
      // All helper invocations are serialized by the package flock wrapper.
      // An unfinished intent with no unit is retained as unknown, never resumed.
      for(const name of fs.readdirSync(state).filter(n=>/^[0-9a-f]{32}\.json$/.test(n)))readReconciled(name.slice(0,-5));
      const receipt={...input,phase:'accepted',acceptedAt:new Date().toISOString(),completionAcknowledged:false};
      atomic(file(p.requestId),receipt);
      try {
        run(SYSTEMD_RUN,['--unit='+UNIT,'--service-type=exec','--collect','--quiet',
          '--property=TimeoutStartSec=infinity','--property=RuntimeMaxSec=6h','--property=UMask=0077',
          '--property=KillMode=control-group','--',node,workerFile,'worker',p.requestId],
          {encoding:'utf8',timeout:15000,env:{PATH:'@PATH@',HOME:'/root',LANG:'C.UTF-8'}});
      }catch(error){
        // systemd may have accepted before the reply was lost. Keep intent and
        // mark uncertainty only after independently checking unit absence.
        const settled=read(p.requestId);
        if(!terminal(settled)&&!running()){settled.phase='interrupted';settled.finishedAt=new Date().toISOString();settled.note='Unit admission unconfirmed; inspect receipt/journal. No retry.';atomic(file(p.requestId),settled);}
        throw Error('Controller admission reply failed; query existing request id, do not resubmit with a new id',{cause:error});
      }
      return receipt;
    },
    status:readReconciled,
    pending(){
      if(!fs.existsSync(state))return [];
      const pending=fs.readdirSync(state).filter(n=>/^[0-9a-f]{32}\.json$/.test(n)).sort()
        .map(n=>readReconciled(n.slice(0,-5))).filter(r=>terminal(r)&&!r.completionAcknowledged);
      if(!pending.length)return [];
      const cursorFile=path.join(state,'completion-cursor.json');
      const cursor=fs.existsSync(cursorFile)?JSON.parse(fs.readFileSync(cursorFile,'utf8')).after:'';
      let start=pending.findIndex(r=>r.requestId>cursor);if(start<0)start=0;
      const batch=[...pending.slice(start),...pending.slice(0,start)].slice(0,32);
      // Durable fair rotation survives Gateway restarts; never removes failed receipts.
      atomic(cursorFile,{after:batch.at(-1).requestId});return batch;
    },
    ack(id,deliveryReceipt){const r=read(id);if(!terminal(r))throw Error('Cannot acknowledge unfinished receipt');
      if(!deliveryReceipt||Object.keys(deliveryReceipt).sort().join(',')!=='channel,messageId'||deliveryReceipt.channel!==r.delivery.channel||typeof deliveryReceipt.messageId!=='string'||!deliveryReceipt.messageId.length||deliveryReceipt.messageId.length>512||/[\r\n\0]/.test(deliveryReceipt.messageId))throw Error('A confirmed matching platform receipt is required');
      r.completionAcknowledged=true;r.notificationReceipt=deliveryReceipt;atomic(file(id),r);return {requestId:id,acknowledged:true};},
    async worker(id){
      const r=read(id);validate({operation:r.operation,revision:r.revision,requestId:r.requestId});
      if(r.phase!=='accepted')throw Error('Runner refuses replay');
      r.phase='running';r.startedAt=new Date().toISOString();atomic(file(id),r);
      const log=path.join(state,id+'.log');const fd=fs.openSync(log,'a',0o600);
      let outcome;
      try {
        const child=launch(controller,[r.operation,r.revision],{stdio:['ignore',fd,fd],env:{PATH:'@PATH@',HOME:'/root',LANG:'C.UTF-8'}});
        outcome=await new Promise(resolve=>{child.once('error',()=>resolve({exitCode:null,signal:null,spawnFailed:true}));child.once('exit',(exitCode,signal)=>resolve({exitCode,signal}));});
      } finally {fs.fsyncSync(fd);fs.closeSync(fd);}
      // Do not infer rollback from exit 1 alone. Root-owned controller log is the proof.
      const logFd=fs.openSync(log,'r');let tail;
      try{const size=fs.fstatSync(logFd).size;const bytes=Buffer.alloc(Math.min(size,8192));fs.readSync(logFd,bytes,0,bytes.length,Math.max(0,size-bytes.length));tail=bytes.toString('utf8');}finally{fs.closeSync(logFd);}
      r.phase=outcome.exitCode===0?'completed':'failed';
      if(outcome.signal||outcome.spawnFailed)r.phase='interrupted';
      if(outcome.exitCode===2&&tail.includes('rollback incomplete:'))r.phase='rollback-incomplete';
      r.rollbackConfirmed=outcome.exitCode===1&&/returned to generation [0-9]+ and \/nix\/store\//.test(tail);
      Object.assign(r,outcome,{finishedAt:new Date().toISOString()});atomic(file(id),r);return r;
    }
  };
}
export async function main(argv,input,{host=createHost(),uid=process.getuid(),sudoUser=process.env.SUDO_USER}={}) {
  if(uid!==0)throw Error('Root-owned host adapter required');
  const [action,id]=argv;
  if(action==='worker'){if(argv.length!==2||sudoUser)throw Error('Worker is systemd-owned only');return await host.worker(id);}
  if(sudoUser!=='openclaw')throw Error('Only the configured Gateway service identity may use the adapter');
  if(action==='submit'&&argv.length===1)return host.submit(JSON.parse(input));
  if(action==='status'&&argv.length===2)return host.status(id);
  if(action==='pending'&&argv.length===1)return host.pending();
  if(action==='ack'&&argv.length===2)return host.ack(id,JSON.parse(input));
  throw Error('Invalid fixed host operation');
}
if(process.argv[1]===import.meta.filename){
  try {const input=['submit','ack'].includes(process.argv[2])?fs.readFileSync(0,'utf8'):'';if(input.length>4096)throw Error('Request too large');console.log(JSON.stringify(await main(process.argv.slice(2),input)));}
  catch(error){console.error(error.message);process.exitCode=1;}
}
