// XRSim acceptance through the real OpenXR action pipeline.
// Usage: node tools/xrsim_audit.mjs <xrsim-repo> <Godot-user-dir> <evidence-dir>
// Launch scenes/xr_audit.tscn with the Meta runtime + Operator layer first.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
const [repo,user,evidence]=process.argv.slice(2);
if(!repo||!user||!evidence) throw Error('Supply xrsim repository, isolated user directory, and evidence directory.');
const {OperatorClient}=await import(pathToFileURL(join(resolve(repo),'dist/backends/operatorLayer.js')));
const {metaxrsimControllerSet:pose,metaxrsimPressButton:press,metaxrsimSetAnalog:analog}=await import(pathToFileURL(join(resolve(repo),'dist/backends/metaxrsimInput.js')));
mkdirSync(evidence,{recursive:true});
const results=[];
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function read(){return JSON.parse(readFileSync(join(user,'xr_audit.json'),'utf8'));}
async function wait(predicate,label,timeout=12000){
 const deadline=Date.now()+timeout;let state;
 while(Date.now()<deadline){try{state=read();if(predicate(state))return state;}catch{} await sleep(60);}
 throw Error(label+' timed out');
}
async function check(label,predicate,timeout){
 const state=await wait(predicate,label,timeout);
 results.push({label,ok:true,state});writeFileSync(join(evidence,'xr-acceptance.json'),JSON.stringify(results,null,2));
 console.log('PASS',label);return state;
}
async function hand(side,pos,quat=[0,0,0,1]){
 const before=read().sample;
 await pose(side,pos,quat,{baseSpace:'view',poseType:'grip'});
 return wait(s=>s.sample>before,'fresh hand pose readback');
}
async function withdraw(side='right'){await analog(side,'squeeze',0);return hand(side,[0,0,-.15]);}
async function poke(id,side='right'){
 await withdraw(side);const pos=read().controls[id].view;return hand(side,[pos[0],pos[1]+.01,pos[2]+.06]);
}
async function grab(id,side='right'){
 await withdraw(side);await hand(side,read().controls[id].view);await analog(side,'squeeze',.7);
 return check('grab '+id,s=>s.hands[side+'_hand'].holding===s.controls[id].path);
}
const client=new OperatorClient();
try{
 await client.connect();
 const instance=await client.callTool('openxr_get_instance_info',{});
 const session=await client.callTool('openxr_get_session_info',{});
 if(instance.json?.application?.name!=='Tank Commander VR'||session.json?.state?.name!=='XR_SESSION_STATE_FOCUSED')throw Error('Wrong application or unfocused XR session');
 writeFileSync(join(evidence,'operator-identity.json'),JSON.stringify({instance,session,profile:await client.callTool('openxr_get_active_interaction_profile',{})},null,2));
 await wait(s=>s.state===0,'menu ready');
 // Aim at the real menu START button from head-relative coordinates.
 const from=[.2,-.2,-.4],to=[.62,-.78,-1.9],d=to.map((v,i)=>v-from[i]),n=Math.hypot(...d);
 for(let i=0;i<3;i++)d[i]/=n;
 const q=[d[1],-d[0],0,1-d[2]],qn=Math.hypot(...q);for(let i=0;i<4;i++)q[i]/=qn;
 await pose('right',from,q,{baseSpace:'view',poseType:'aim'});
 await press('right','trigger',.4);
 await check('menu trigger starts real tank mission',s=>s.state===1&&!!s.tank&&s.calibrated);
 await withdraw('left');await withdraw('right');
 await poke('battery');await check('physical poke enables battery',s=>s.tank.battery);
 const sample=read().sample;await check('held switch contact stays on',s=>s.sample>sample+7&&s.tank.battery);
 await poke('fuel_cover');await check('cover opens',s=>s.controls.fuel_cover.open);
 await poke('fuel_pump');await check('guarded fuel switch works after withdrawal',s=>s.tank.fuel);
 await poke('starter');await check('held starter starts engine',s=>s.tank.engine,15000);
 await grab('gear');let p=read().controls.gear.view;await hand('right',[p[0],p[1],p[2]-.12]);
 await check('physical gear lever selects drive',s=>s.tank.gear===1);
 await withdraw();
 await grab('tiller_r');
 await check('grabbing driving control does not fire cannon',s=>s.tank.loaded&&s.tank.ammo===40);
 await analog('right','squeeze',.45);
 await check('grip hysteresis retains control at 45 percent',s=>s.hands.right_hand.grip<.5&&s.hands.right_hand.holding===s.controls.tiller_r.path);
 await withdraw();await check('grip release clears control',s=>s.hands.right_hand.holding==='');
 await grab('grip');p=read().controls.grip.view;await hand('right',[p[0]+.035,p[1],p[2]-.025]);
 await check('physical turret stick deflects',s=>s.controls.grip.deflection[0]>.2);
 await analog('right','trigger',.8);
 await check('turret trigger fires without driving tank',s=>!s.tank.loaded&&Math.abs(s.tank.speed)<.1);
 await analog('right','trigger',0);await withdraw();
 await grab('breech');p=read().controls.breech.view;await hand('right',[p[0],p[1],p[2]-.22]);
 await check('reachable reload lever chambers next shell',s=>s.tank.loaded&&s.tank.ammo===39);
 await withdraw();
 await grab('radio_volume','left');p=read().controls.radio_volume.view;
 const old=read().controls.radio_volume.value;
 await hand('left',p,[-Math.sin(Math.PI/8),0,0,Math.cos(Math.PI/8)]);
 await check('wrist twist turns wall-mounted radio knob',s=>s.controls.radio_volume.value>old+.1);
 await withdraw('left');
 await poke('ir');await check('near-field IR switch enables sight',s=>s.controls.ir.on);
 const start=read();
 const finish=await check('thermal refresh continues at bounded rate',s=>s.sample>start.sample+10&&s.tank.thermal_updates>start.tank.thermal_updates);
 const updates=finish.tank.thermal_updates-start.tank.thermal_updates, ticks=finish.tank.physics_frames-start.tank.physics_frames;
 if(updates>ticks*30/72+2)throw Error('Thermal refresh exceeded 30Hz physics budget');
 console.log('PASS thermal scheduling budget',updates,'updates in',ticks,'physics ticks');
 await poke('ir');await check('second distinct touch turns IR off',s=>!s.controls.ir.on);
 await grab('tiller_l','left');await press('left','menu',.4);
 await check('pause clears held physical control',s=>s.paused&&s.hands.left_hand.holding==='');
 await press('left','menu',.4);await check('pause button resumes mission',s=>!s.paused&&s.state===1);
 console.log('XRSim acceptance complete:',results.length,'checks.');
}catch(error){
 results.push({label:error.message,ok:false,state:read()});writeFileSync(join(evidence,'xr-acceptance.json'),JSON.stringify(results,null,2));
 console.error(error.message);process.exitCode=1;
}finally{
 client.close();
 for(const side of ['left','right']){try{await analog(side,'trigger',0);await analog(side,'squeeze',0);}catch{}}
 setTimeout(()=>process.exit(process.exitCode??0),150);
}
