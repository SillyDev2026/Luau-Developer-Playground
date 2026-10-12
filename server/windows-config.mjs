// Pure, testable Windows launcher settings. Secrets are never bundled.
import { join } from 'node:path';
import { homedir } from 'node:os';

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
