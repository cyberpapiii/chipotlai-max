import {
  type LanguageModelV2,
  type LanguageModelV2StreamPart,
} from "@ai-sdk/provider"
import {
  type FetchFunction,
  generateId,
} from "@ai-sdk/provider-utils"

export interface AdventistProviderSettings {
  /**
   * Base URL for the Adventist IA API calls.
   */
  baseURL?: string

  /**
   * Custom fetch implementation.
   */
  fetch?: FetchFunction
}

export interface AdventistProvider {
  (modelId: string): LanguageModelV2
  languageModel(modelId: string): LanguageModelV2
  chat(modelId: string): LanguageModelV2
  responses(modelId: string): LanguageModelV2
  textEmbeddingModel(modelId: string): any
  imageModel(modelId: string): any
}

export function createAdventist(options: AdventistProviderSettings = {}): AdventistProvider {
  const baseURL = options.baseURL ?? "https://ia.adventistas.org/api/chat"

  const createLanguageModel = (modelId: string): LanguageModelV2 => {
    return new AdventistLanguageModel(modelId, {
      baseURL,
      fetch: options.fetch,
    })
  }

  const provider = function (modelId: string) {
    return createLanguageModel(modelId)
  }

  provider.languageModel = createLanguageModel
  provider.chat = createLanguageModel
  provider.responses = createLanguageModel
  provider.textEmbeddingModel = (modelId: string) => {
      throw new Error("Adventist IA does not support text embedding models")
  }
  provider.imageModel = (modelId: string) => {
      throw new Error("Adventist IA does not support image models")
  }

  return provider as any
}

class AdventistLanguageModel implements LanguageModelV2 {
  readonly specificationVersion = "v2"
  readonly modelId: string
  readonly provider = "adventist"

  private readonly config: {
    baseURL: string
    fetch?: FetchFunction
  }

  constructor(modelId: string, config: { baseURL: string; fetch?: FetchFunction }) {
    this.modelId = modelId
    this.config = config
  }

  get defaultObjectGenerationMode() {
    return undefined
  }

  get supportedUrls() {
      return {}
  }

  private async fetchSSE(prompt: string) {
    const fetchFn = this.config.fetch ?? fetch
    const response = await fetchFn(this.config.baseURL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Referer": "https://ia.adventistas.org/",
        "Accept": "text/event-stream",
      },
      body: JSON.stringify({
        query: prompt,
        user_id: "anonymous",
        conversation_id: null,
      }),
    })

    if (!response.ok) {
      const body = await response.text()
      throw new Error(`Adventist IA API error: ${response.status} ${body}`)
    }

    if (!response.body) {
      throw new Error("Adventist IA API error: No response body")
    }

    return response
  }

  async doGenerate(options: Parameters<LanguageModelV2["doGenerate"]>[0]): Promise<Awaited<ReturnType<LanguageModelV2["doGenerate"]>>> {
    const { prompt } = options
    const lastMessage = prompt[prompt.length - 1]
    const content = lastMessage?.content[0]
    const query = content && typeof content === "object" && "text" in content ? content.text : ""

    const response = await this.fetchSSE(query)
    const reader = response.body!.getReader()
    const decoder = new TextDecoder()
    let text = ""
    let buffer = ""

    while (true) {
      const { done, value } = await reader.read()
      if (done) break
      
      buffer += decoder.decode(value, { stream: true })
      const lines = buffer.split("\n")
      buffer = lines.pop() ?? ""

      for (const line of lines) {
        if (line.startsWith("data: ")) {
          try {
            const data = JSON.parse(line.slice(6))
            if (data.event === "agent_message" && data.answer) {
              text += data.answer
            }
          } catch (e) {}
        }
      }
    }

    return {
      text,
      content: [{ type: "text", text }],
      finishReason: "stop",
      usage: { promptTokens: 0, completionTokens: 0 } as any,
      warnings: [],
    } as any
  }

  async doStream(options: Parameters<LanguageModelV2["doStream"]>[0]): Promise<Awaited<ReturnType<LanguageModelV2["doStream"]>>> {
    const { prompt } = options
    const lastMessage = prompt[prompt.length - 1]
    const content = lastMessage?.content[0]
    const query = content && typeof content === "object" && "text" in content ? content.text : ""

    const response = await this.fetchSSE(query)
    const reader = response.body!.getReader()
    const decoder = new TextDecoder()
    
    const stream = new ReadableStream<LanguageModelV2StreamPart>({
      async start(controller) {
        const textPartId = generateId()
        
        // Emit text-start
        controller.enqueue({
          type: "text-start",
          id: textPartId,
        } as any)

        let buffer = ""
        try {
          while (true) {
            const { done, value } = await reader.read()
            if (done) {
              // Emit text-end before finish
              controller.enqueue({
                type: "text-end",
                id: textPartId,
              } as any)

              controller.enqueue({
                type: "finish",
                finishReason: "stop",
                usage: { promptTokens: 0, completionTokens: 0 } as any,
              })
              controller.close()
              break
            }

            buffer += decoder.decode(value, { stream: true })
            const lines = buffer.split("\n")
            buffer = lines.pop() ?? ""

            for (const line of lines) {
              if (line.trim() === "") continue
              if (line.startsWith("data: ")) {
                try {
                  const data = JSON.parse(line.slice(6))
                  if (data.event === "agent_message" && data.answer) {
                    controller.enqueue({
                      type: "text-delta",
                      id: textPartId,
                      delta: data.answer,
                    })
                  }
                } catch (e) {}
              }
            }
          }
        } catch (e) {
          controller.error(e)
        }
      }
    })

    return {
      stream,
      response: { headers: Object.fromEntries(response.headers.entries()) },
      warnings: [],
    } as any
  }
}
