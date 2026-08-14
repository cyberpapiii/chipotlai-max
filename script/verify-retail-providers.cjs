const fs = require('fs');
const os = require('os');
const path = require('path');
const child = require('child_process');

const src = fs.readFileSync('packages/opencode/src/provider/provider.ts', 'utf8');
const launch = fs.readFileSync('start-chipotlai.sh', 'utf8');

const want = [
  ['home-depot-magic-apron', 'magic-apron-1', 'HOME_DEPOT_MAGIC_APRON_BASE_URL'],
  ['sephora-ai-beauty-chat', 'beauty-chat-1', 'SEPHORA_AI_BEAUTY_CHAT_BASE_URL'],
  ['nordstrom-rosie', 'rosie-1', 'NORDSTROM_ROSIE_BASE_URL'],
  ['lowes-mylow', 'mylow-1', 'LOWES_MYLOW_BASE_URL'],
  ['ikea-billie', 'billie-1', 'IKEA_BILLIE_BASE_URL'],
  ['expedia-virtual-agent', 'virtual-agent-1', 'EXPEDIA_VIRTUAL_AGENT_BASE_URL'],
  ['amazon-rufus', 'rufus-1', 'AMAZON_RUFUS_BASE_URL'],
];

for (const [provider, model, env] of want) {
  if (!src.includes(`"${provider}"`)) throw new Error(`Missing provider ${provider}`);
  if (!src.includes(`"${model}"`)) throw new Error(`Missing model ${model}`);
  if (!launch.includes(env)) throw new Error(`Launcher missing ${env}`);
}

if (!src.includes('"@ai-sdk/openai-compatible"')) {
  throw new Error('Retail providers must use the bundled OpenAI-compatible SDK');
}

for (const [provider, model] of want) {
  const cfg = fs.mkdtempSync(path.join(os.tmpdir(), 'chipotlai-opencode-'));
  const out = child.execFileSync(
    'bun',
    ['run', '--conditions=browser', 'src/index.ts', 'models', provider, '--verbose'],
    {
      cwd: 'packages/opencode',
      env: { ...process.env, XDG_CONFIG_HOME: cfg },
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );

  if (!out.includes(`${provider}/${model}`)) throw new Error(`CLI missing ${provider}/${model}`);
  if (!out.includes('"@ai-sdk/openai-compatible"')) throw new Error(`CLI provider ${provider} is not OpenAI-compatible`);
}

console.log(`verified ${want.length} OpenCode retail providers`);
