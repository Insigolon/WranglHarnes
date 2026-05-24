# Model Client Adapters

Full adapter implementations for each supported lightweight model runtime.

---

## Ollama

```python
import httpx, json

class OllamaClient:
    def __init__(self, base_url="http://localhost:11434", model="llama3.2"):
        self.base_url = base_url
        self.model = model

    def complete(self, system: str, messages: list, tools: list = None) -> str:
        system_with_tools = system
        if tools:
            system_with_tools += f"\n\nAvailable tools (respond as JSON with 'tool' and 'args' keys):\n{json.dumps(tools, indent=2)}"

        payload = {
            "model": self.model,
            "messages": [{"role": "system", "content": system_with_tools}] + messages,
            "stream": False,
            "options": {"temperature": 0.1}  # Low temp for tool-calling reliability
        }
        resp = httpx.post(f"{self.base_url}/api/chat", json=payload, timeout=120)
        resp.raise_for_status()
        return resp.json()["message"]["content"]

    def list_models(self) -> list[str]:
        resp = httpx.get(f"{self.base_url}/api/tags")
        return [m["name"] for m in resp.json()["models"]]
```

**TypeScript:**
```typescript
class OllamaClient {
  constructor(private baseUrl = "http://localhost:11434", private model = "llama3.2") {}

  async complete(system: string, messages: Message[], tools: string[] = []): Promise<string> {
    const systemWithTools = tools.length
      ? `${system}\n\nAvailable tools (JSON with 'tool' and 'args'):\n${JSON.stringify(tools)}`
      : system;
    const res = await fetch(`${this.baseUrl}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: this.model,
        messages: [{ role: "system", content: systemWithTools }, ...messages],
        stream: false,
        options: { temperature: 0.1 },
      }),
    });
    const data = await res.json();
    return data.message.content;
  }
}
```

**Best models for tool-calling via Ollama (2025):**
- `qwen2.5:7b` — best tool-call JSON compliance at 7B
- `llama3.2:3b` — fast, decent JSON
- `phi4:14b` — best reasoning per param count
- `mistral-nemo` — good at following structured formats

---

## llama.cpp / LM Studio (OpenAI-compatible)

Both expose an OpenAI-compatible `/v1/chat/completions` endpoint.

```python
import httpx

class LlamaCppClient:
    def __init__(self, base_url="http://localhost:8080", model="local"):
        self.base_url = base_url
        self.model = model

    def complete(self, system: str, messages: list, tools: list = None) -> str:
        msgs = [{"role": "system", "content": system}] + messages
        if tools:
            msgs[0]["content"] += f"\n\nTools: {tools}"

        payload = {
            "model": self.model,
            "messages": msgs,
            "temperature": 0.1,
            "max_tokens": 1024,
            # Use grammar-based JSON enforcement if llama.cpp supports it:
            # "grammar": TOOL_CALL_GRAMMAR,
        }
        resp = httpx.post(f"{self.base_url}/v1/chat/completions", json=payload, timeout=120)
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]
```

**llama.cpp grammar enforcement** (highly recommended for tool calls):
```
# Pass as "grammar" param to force valid JSON output
root   ::= object
object ::= "{" ws "\"tool\"" ws ":" ws string ws "," ws "\"args\"" ws ":" ws object ws "}"
```

---

## Hugging Face Transformers

```python
from transformers import pipeline
import json, re

class HFClient:
    def __init__(self, model_name="Qwen/Qwen2.5-7B-Instruct", device="auto"):
        self.pipe = pipeline(
            "text-generation",
            model=model_name,
            device_map=device,
            torch_dtype="auto",
        )

    def complete(self, system: str, messages: list, tools: list = None) -> str:
        system_content = system
        if tools:
            system_content += f"\n\nTools available:\n{json.dumps(tools, indent=2)}"

        chat = [{"role": "system", "content": system_content}] + messages
        outputs = self.pipe(
            chat,
            max_new_tokens=512,
            do_sample=False,      # greedy for determinism
            temperature=None,
            top_p=None,
        )
        # Extract only the newly generated tokens
        return outputs[0]["generated_text"][-1]["content"]
```

**Notes:**
- Use `do_sample=False` (greedy) for tool-calling — sampling increases malformed JSON rate
- Models with built-in tool-call support: `Qwen2.5-7B-Instruct`, `Mistral-7B-Instruct-v0.3`, `Meta-Llama-3.1-8B-Instruct`
- For < 4GB VRAM: use `load_in_4bit=True` via `BitsAndBytesConfig`

```python
# 4-bit quantization for small GPUs
from transformers import BitsAndBytesConfig
bnb = BitsAndBytesConfig(load_in_4bit=True)
pipe = pipeline("text-generation", model=model_name, model_kwargs={"quantization_config": bnb})
```