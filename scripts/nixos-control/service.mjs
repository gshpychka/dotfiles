import {validateDelivery} from './core.mjs';
export function registerCompletionService(api,transport) {
 let task;
 api.registerService({id:'nixos-control-completions',apiVersion:2,
  async start(ctx){
   const tick=async()=>{
    for(const r of await transport.pendingCompletions()){
     ctx.scheduler.signal.throwIfAborted();
     const route=validateDelivery(r.delivery);
     // Public native adapter, fixed to the trusted route captured at tool admission.
     // Do not infer a destination from last-route state or run an owner-like agent.
     const adapter=await api.runtime.channel.outbound.loadAdapter(route.channel);
     if(!adapter?.sendText)throw Error('Original completion channel unavailable; receipt retained');
     const assertCurrent=()=>{
      ctx.scheduler.signal.throwIfAborted();
      if(api.runtime.config.current().channels?.[route.channel]?.enabled===false)throw Error('Original completion channel disabled');
     };
     assertCurrent();
     const rollback=r.rollbackConfirmed?' Rollback confirmed.':r.phase==='rollback-incomplete'?' Rollback incomplete.':'';
     const text='NixOS '+r.operation+' '+r.revision.slice(0,12)+': '+r.phase+'.'+rollback+' Request '+r.requestId+'.';
     const sent=await adapter.sendText({cfg:api.runtime.config.current(),...route,text,
       signal:ctx.scheduler.signal,assertDirectAdapterHandoff:assertCurrent});
     // A reporting run/queued event/silent outcome is NOT platform delivery proof.
     if(!sent||sent.channel!==route.channel||typeof sent.messageId!=='string'||!sent.messageId.length||
       (sent.outcome!==undefined&&sent.outcome!=='sent'))throw Error('No confirmed platform completion receipt');
     await transport.ackCompletion(r.requestId,{channel:sent.channel,messageId:sent.messageId});
    }
   };
   task=ctx.scheduler.schedule({id:'receipts',delayMs:1000,everyMs:15000,run:async()=>{
    try{await tick();ctx.serviceHealth?.clearFailure();}catch(error){ctx.serviceHealth?.reportFailure(error);ctx.logger.error('NixOS completion delivery failed; durable receipts retained');}
   }});
  },async stop(){await task?.stop();task=undefined;}
 });
}
