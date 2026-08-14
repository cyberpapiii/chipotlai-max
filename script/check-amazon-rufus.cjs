const fs = require('fs')
const src = fs.readFileSync('packages/opencode/src/provider/provider.ts', 'utf8')
const launch = fs.readFileSync('start-chipotlai.sh', 'utf8')
const schema = fs.readFileSync('packages/opencode/src/provider/schema.ts', 'utf8')

const checks = [
  ['ProviderID in schema', schema.includes('amazonRufus: schema.makeUnsafe')],
  ['bot in bots array', src.includes('"amazon-rufus", "Amazon Rufus", "rufus-1"')],
  ['CUSTOM_LOADERS entry', src.includes('async "amazon-rufus"()')],
  ['autoload conditional on env', src.includes('Env.get("AMAZON_RUFUS_BASE_URL")') && src.includes('if (!baseUrl) return { autoload: false }')],
  ['env-var URL wiring in loop', src.includes('bot[0].toUpperCase().replace(/-/g, "_")') && src.includes('_BASE_URL')],
  ['URL uses env-resolved value', src.includes('url: baseUrl,')],
  ['launcher env-var echo', launch.includes('AMAZON_RUFUS_BASE_URL') && launch.includes('Amazon Rufus')],
]

let bad = 0
for (const [name, ok] of checks) {
  console.log((ok ? 'OK  ' : 'FAIL') + ' ' + name)
  if (!ok) bad++
}
process.exit(bad ? 1 : 0)
