import { resolve } from 'node:path';
import { createCollabServer } from './collab.mjs';

const port=Number(process.env.PORT||8787);
const host=process.env.HOST||'0.0.0.0';
const dataFile=resolve(process.env.COLLAB_DATA_FILE||'./server/data/workspaces.json');
const allowedOrigins=(process.env.ALLOWED_ORIGINS||'https://sillydev2026.github.io,http://127.0.0.1:4173,http://localhost:4173')
  .split(',').map(x=>x.trim()).filter(Boolean);
if(!Number.isInteger(port)||port<0||port>65535)throw Error('Invalid PORT');
const {server}=createCollabServer({dataFile,allowedOrigins});
server.listen(port,host,()=>{
  console.log('LuauForge collaboration API listening on '+host+':'+port+' (persistent file: '+dataFile+')');
});
