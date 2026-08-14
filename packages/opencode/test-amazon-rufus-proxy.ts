// End-to-end test: real proxy -> mock Amazon -> back to a real OpenAI client.
// Starts the mock Amazon server, then the proxy pointed at it, then
// invokes the proxy with the same createOpenAICompatible call shape
// OpenCode uses internally. Verifies the round-trip:
//   OpenAI request -> proxy -> Amazon request format -> mock -> response
//   -> proxy extracts text -> OpenAI response.

import { spawn } from "bun"

const MOCK_PORT = 3999
const PROXY_PORT = 3998

async function start(cmd: string[], env: Record<string, string>) {
  const proc = spawn({
    cmd,
    env: { ...process.env, ...env },
    stdout: "inherit",
    stderr: "inherit",
  })
  await new Promise((r) => setTimeout(r, 800))
  return proc
}

async function stop(proc: ReturnType<typeof spawn>) {
  proc.kill()
  await proc.exited
}

const mock = await start(
  ["bun", "run", "../../script/mock-amazon-rufus.ts"],
  { MOCK_PORT: String(MOCK_PORT) },
)

const proxy = await start(
  ["bun", "run", "../../script/amazon-rufus-proxy.ts"],
  {
    PORT: String(PROXY_PORT),
    AMAZON_RUFUS_URL: `http://localhost:${MOCK_PORT}/rufus/cl/streaming`,
    AMAZON_RUFUS_COOKIE: "session-id=mock-session; ubid-main=mock",
    AMAZON_RUFUS_CSRF_TOKEN: "mock-csrf-token-1234567890",
    AMAZON_RUFUS_FLOW_CLOSURE_ID: "mock-flow-closure-id",
    AMAZON_RUFUS_IMPRESSIONS_KEY: "mock-impressions-key",
    AMAZON_RUFUS_REQUEST_ID: "mock-request-id",
    AMAZON_RUFUS_SESSION_ID: "mock-session-id",
    AMAZON_RUFUS_THREAD_ID: "mock-thread-id",
  },
)

try {
  const { createOpenAICompatible } = await import("@ai-sdk/openai-compatible")
  const { generateText } = await import("ai")

  const provider = createOpenAICompatible({
    name: "amazon-rufus",
    baseURL: `http://localhost:${PROXY_PORT}/v1`,
    apiKey: "burrito-2026",
  })

  const result = await generateText({
    model: provider("rufus-1"),
    prompt: "ping from the e2e test",
  })

  console.log("---")
  console.log("baseURL:    ", `http://localhost:${PROXY_PORT}/v1`)
  console.log("model:      ", "amazon-rufus/rufus-1")
  console.log("reply:      ", result.text)
  console.log("---")

  if (!result.text.includes("Mock Rufus reply: ping from the e2e test")) {
    console.error("FAIL: reply did not contain expected text")
    process.exit(1)
  }
  console.log("OK: round-trip works")
} finally {
  await stop(proxy)
  await stop(mock)
}
