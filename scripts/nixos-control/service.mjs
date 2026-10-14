export function registerCompletionService(api,transport) {
 let task;
 api.registerService({id:'nixos-control-completions',apiVersion:2,
  async start(ctx){
   const tick=async()=>{
    for(const r of await transport.pendingCompletions()){
     if(ctx.scheduler.signal.aborted)return;
     const text='NixOS control receipt '+r.requestId+': '+JSON.stringify(r)+'. Report this actual result to the owner; do not initiate/replay another deployment.';
     const accepted=api.runtime.system.enqueueSystemEvent(text,{agentId:r.agentId,sessionKey:r.sessionKey,contextKey:'nixos-control:'+r.requestId,replace:true});
     if(!accepted)continue;
     // Join one real routed run, not a timer-only wake. Keep outbox on skipped/
     // failed/offline/draining runs and retry after restart. Delivery is at-least-once.
     const result=await api.runtime.system.runHeartbeatOnce({agentId:r.agentId,sessionKey:r.sessionKey,reason:'nixos-control-completion',heartbeat:{target:'last'}});
     if(result.status==='ran')await transport.ackCompletion(r.requestId);
    }
   };
   task=ctx.scheduler.schedule({id:'receipts',delayMs:1000,everyMs:15000,run:async()=>{
    try{await tick();ctx.serviceHealth?.clearFailure();}catch(error){ctx.serviceHealth?.reportFailure(error);ctx.logger.error('NixOS completion reconciliation failed; durable receipts retained');}
   }});
  },async stop(){await task?.stop();task=undefined;}
 });
}
