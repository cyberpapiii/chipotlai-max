// End-to-end test: invoke the amazon-rufus/rufus-1 slot the same way OpenCode does
// (via @ai-sdk/openai-compatible + generateText), with AMAZON_RUFUS_BASE_URL pointed
// at the mock backend. Confirms the wire format works and a reply round-trips.

import { createOpenAICompatible } from "@ai-sdk/openai-compatible"
import { generateText } from "ai"

const baseURL = process.env.AMAZON_RUFUS_BASE_URL
if (!baseURL) {
  console.error("AMAZON_RUFUS_BASE_URL is not set")
  process.exit(1)
}

const provider = createOpenAICompatible({
  name: "amazon-rufus",
  baseURL,
  apiKey: "burrito-2026",
})

const model = provider("rufus-1")

const result = await generateText({
  model,
  prompt: "ping",
})

console.log("---")
console.log("baseURL:", baseURL)
console.log("model  :", "amazon-rufus/rufus-1")
console.log("reply  :", result.text)
console.log("usage  :", result.usage)
console.log("---")
