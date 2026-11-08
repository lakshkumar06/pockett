import {pathToFileURL} from 'node:url';
import {service} from './spacetime.ts';
import {build,type Trace} from './agent.ts';
import {Photon} from './photon.ts';
export async function tick(invoke=service,agent=build){
  const {jobs}=await invoke('GET','jobs');
  for(const pending of jobs){
    let job:any;try{job=await invoke('POST',`jobs/${pending.id}/claim`);}catch{continue;}
    let spec=job.spec,trace:Trace[]=[];
    try{
      const result=await agent(job.prompt,job.spec,async(s,t)=>{spec=s;trace=t;await invoke('POST',`jobs/${job.id}/save`,{lease:job.lease,status:'building',spec,trace});});
      await invoke('POST',`jobs/${job.id}/save`,{lease:job.lease,status:'ready',...result});
    }catch(e){await invoke('POST',`jobs/${job.id}/save`,{lease:job.lease,status:'failed',spec,trace,error:e instanceof Error?e.message:'Build failed'});}
  }
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  const photon=process.env.PHOTON_API_KEY&&process.env.PHOTON_PROJECT_ID&&process.env.PHOTON_SENDER_ID?new Photon(process.env.PHOTON_API_KEY,process.env.PHOTON_PROJECT_ID,process.env.PHOTON_SENDER_ID):null;
  let running=true;process.on('SIGTERM',()=>{running=false;});process.on('SIGINT',()=>{running=false;});
  console.log('Pocket worker ready; '+(photon?'Photon polling enabled':'Photon disabled (configure credentials to enable)'));
  // Independent loops keep chat responsive while a model is building. Each loop is single-flight.
  async function loop(task:()=>Promise<void>,label:string){while(running){try{await task();}catch{console.error(label+' cycle failed; retrying');}await new Promise(r=>setTimeout(r,5000));}}
  await Promise.all([loop(()=>tick(),'Build'),...(photon?[loop(()=>photon.tick(),'Photon')]:[])]);
}
