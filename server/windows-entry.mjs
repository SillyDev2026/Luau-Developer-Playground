// Windows single-executable entry point. Bundle with esbuild, then Node SEA.
// Run outside a repo: all mutable data is stored in %LOCALAPPDATA%\LuauForgeServer.
import { mkdirSync } from 'node:fs';
import { createCollabServer } from './collab.mjs';
import { windowsServerConfig } from './windows-config.mjs';

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
startWindowsServer();
