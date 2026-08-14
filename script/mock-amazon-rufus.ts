// Mock Amazon Rufus endpoint for testing the proxy.
// Listens on $MOCK_PORT (default 3002), expects POST in Amazon's request
// format (anti-csrftoken-a2z header, queryContext body), returns a JSON
// response with a `content` field that the proxy's extractor should pick up.

const port = Number(process.env.MOCK_PORT ?? 3002)

Bun.serve({
  port,
  async fetch(req) {
    const url = new URL(req.url)
    if (url.pathname.endsWith("/rufus/cl/streaming") && req.method === "POST") {
      const csrf = req.headers.get("anti-csrftoken-a2z")
      if (!csrf) {
        return Response.json(
          { error: "missing anti-csrftoken-a2z" },
          { status: 403 },
        )
      }
      const body = (await req.json()) as {
        queryContext?: { query?: string }
      }
      const prompt = body.queryContext?.query ?? ""
      console.log(
        `[mock-amazon] POST queryContext.query=${JSON.stringify(prompt)} csrf=${csrf.slice(0, 8)}...`,
      )
      return Response.json({
        id: "mock-rfn-1",
        content: `Mock Rufus reply: ${prompt}`,
      })
    }
    return new Response("not found", { status: 404 })
  },
})

console.log(`[mock-amazon] listening on http://localhost:${port}`)
