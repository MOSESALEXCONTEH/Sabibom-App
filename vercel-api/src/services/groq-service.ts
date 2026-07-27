import {getEnv} from "../config/env";
import {errors} from "../utils/api-errors";
import {extractJsonObject} from "../utils/normalize";

type ChatMessage = {role: "system" | "user" | "assistant"; content: string};

/**
 * Groq periodically decommissions models (e.g. llama-3.3-70b-versatile on
 * 2026-08-16). If the configured model fails, retry with these known-good
 * replacements so Sabi keeps working without a redeploy.
 */
const FALLBACK_MODELS = ["openai/gpt-oss-120b", "openai/gpt-oss-20b"];

function modelsToTry(): string[] {
  const env = getEnv();
  return [env.groqModel, ...FALLBACK_MODELS.filter((m) => m !== env.groqModel)];
}

async function groqCompletion(options: {
  messages: ChatMessage[];
  temperature: number;
  jsonMode: boolean;
}): Promise<string | null> {
  const env = getEnv();
  let lastFailure = "";

  for (const model of modelsToTry()) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 35_000);
    try {
      const response = await fetch(
        "https://api.groq.com/openai/v1/chat/completions",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${env.groqApiKey}`,
            "Content-Type": "application/json",
          },
          signal: controller.signal,
          body: JSON.stringify({
            model,
            temperature: options.temperature,
            ...(options.jsonMode
              ? {response_format: {type: "json_object"}}
              : {}),
            messages: options.messages,
          }),
        },
      );

      if (response.ok) {
        const body = (await response.json()) as {
          choices?: Array<{message?: {content?: string}}>;
        };
        return body.choices?.[0]?.message?.content?.trim() ?? "";
      }

      const errorBody = await response.text().catch(() => "");
      lastFailure = `model=${model} status=${response.status} body=${errorBody.slice(0, 500)}`;
      console.error(`[groq-service] request failed: ${lastFailure}`);

      // Auth and rate-limit problems affect every model; stop retrying.
      if (response.status === 401 || response.status === 403) {
        throw errors.unavailable();
      }
      if (response.status === 429) {
        throw errors.rateLimited();
      }
      // 400/404 (bad or decommissioned model) → try the next model.
    } catch (error) {
      if (error && typeof error === "object" && "status" in error) {
        throw error;
      }
      lastFailure = `model=${model} error=${String(error).slice(0, 300)}`;
      console.error(`[groq-service] request threw: ${lastFailure}`);
    } finally {
      clearTimeout(timeout);
    }
  }

  console.error(`[groq-service] all models failed. last: ${lastFailure}`);
  return null;
}

export async function groqChatJson(options: {
  system: string;
  user: string;
  temperature?: number;
}): Promise<unknown> {
  const content = await groqCompletion({
    messages: [
      {role: "system", content: options.system},
      {role: "user", content: options.user},
    ],
    temperature: options.temperature ?? 0.1,
    jsonMode: true,
  });
  if (content === null) {
    throw errors.unavailable();
  }
  if (!content) {
    throw errors.invalidArgument(
      "I couldn’t understand that safely. Please rephrase or enter the sale manually.",
    );
  }
  return extractJsonObject(content);
}

export async function groqChatText(options: {
  system: string;
  user: string;
  temperature?: number;
}): Promise<string | null> {
  const content = await groqCompletion({
    messages: [
      {role: "system", content: options.system},
      {role: "user", content: options.user},
    ],
    temperature: options.temperature ?? 0.2,
    jsonMode: false,
  });
  return content || null;
}
