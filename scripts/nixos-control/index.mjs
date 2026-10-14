import {definePluginEntry} from 'openclaw/plugin-sdk/plugin-entry';
import {registerControl} from './core.mjs';
import {createTransport} from './transport.mjs';
import {registerCompletionService} from './service.mjs';
export default definePluginEntry({id:'nixos-control',name:'NixOS Control',description:'Owner-authorized fixed hoard NixOS controller with durable receipts.',
 register(api){
  const transport=createTransport();registerControl(api,transport);
  api.registerTool({contextVersion:2,create(context){
   if(context.senderIsOwner!==true||typeof context.assertInvocationCurrent!=='function'||context.sandboxed)return null;
   return {name:'nixos_control_status',label:'NixOS Control Status',description:'Read the durable receipt of an admitted NixOS operation.',
    parameters:{type:'object',additionalProperties:false,required:['requestId'],properties:{requestId:{type:'string',minLength:32,maxLength:32,pattern:'^[0-9a-f]{32}$'}}},
    async execute(_id,p){if(Object.keys(p).join(',')!=='requestId')throw Error('Invalid status request');
     const receipt=await transport.status(p.requestId,context.assertInvocationCurrent);
     context.assertInvocationCurrent();
     // Root receipts are private to owner invocations; do not disclose in other contexts.
     return {content:[{type:'text',text:JSON.stringify(receipt)}],details:{receipt}};
    }};
  }},{name:'nixos_control_status',optional:true});
  registerCompletionService(api,transport);
 }});
