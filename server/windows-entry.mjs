// Windows single-executable entry point. Bundle with esbuild, then Node SEA.
// Run outside a repo: all mutable data is stored in %LOCALAPPDATA%\LuauForgeServer.
import { join } from 'node:path';
import { homedir } from 'node:os';
import { mkdirSync } from 'node:fs';
import { createCollabServer } from './collab.mjs';

export function windowsDataDirectory(env=process.env){
  return join(env.LOCALAPPDATA||join(homedir(),'AppData','Local'),'LuauForgeServer');
}
export function windowsServerConfig(env=process.env){
  const directory=windowsDataDirectory(env);
  const port=Number(env.PORT||8787);
  const host=env.HOST||'127.0.0.1';
  if(!Number.isInteger(port)||port<1||port>65535)throw Error('PORT must be between 1 and 65535');
  const allowedOrigins=(env.ALLOWED_ORIGINS||
    'https://sillydev2026.github.io,http://127.0.0.1:4173,http://localhost:4173')
    .split(',').map(x=>x.trim()).filter(Boolean);
  return {
    port,host,directory,
    dataFile:env.COLLAB_DATA_FILE||join(directory,'workspaces.json'),
    feedbackDataFile:env.FEEDBACK_DATA_FILE||join(directory,'feedback.json'),
    allowedOrigins,discordBotToken:env.DISCORD_BOT_TOKEN||'',
    discordChannels:{
      suggestion:env.DISCORD_SUGGESTIONS_FORUM_ID||'1558939401394851850',
      bug:env.DISCORD_BUG_REPORTS_FORUM_ID||'1558939354234093638'
    }
  };
}
export function startWindowsServer(env=process.env){
  const config=windowsServerConfig(env);
  mkdirSync(config.directory,{recursive:true});
  const {server}=createCollabServer(config);
  server.on('error',error=>{
    if(error.code==='EADDRINUSE')console.error('Port '+config.port+' is already in use. Close the other server or set PORT.');
    else console.error('LuauForge server could not start:',error.message);
    process.exitCode=1;
  });
  server.listen(config.port,config.host,()=>{
    console.log('\n=========================================');
    console.log('  LuauForge Node Server · Windows x64');
    console.log('=========================================');
    console.log('Server: http://'+config.host+':'+config.port);
    console.log('Health: http://'+config.host+':'+config.port+'/health');
    console.log('Storage: '+config.directory);
    console.log('Discord feedback: '+(config.discordBotToken?'token configured':'disabled (optional)'));
    console.log('\nKeep this window open while using the server.');
    console.log('Use http://127.0.0.1:'+config.port+' as the API URL on LuauForge.');
    console.log('For teammates on other devices, use a trusted HTTPS reverse proxy/tunnel.');
    console.log('Do not put the Discord bot token in the website.\n');
  });
  return server;
}
if(process.env.LUAUFORGE_SERVER_SMOKE!=='module-only')startWindowsServer();
