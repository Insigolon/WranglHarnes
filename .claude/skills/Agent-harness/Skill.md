---
name: agent-harness
description: >
  Build, debug, and improve skill-based multiagent harnesses for lightweight local models (Ollama, llama.cpp/LM Studio, Hugging Face Transformers). Use this skill whenever the user wants to design an agent loop from scratch, wire up tools or MCP servers scoped to a skill, build a skill-routing layer, add evaluation/guardrails to their loop, or debug a flaky/looping/stuck agent. Trigger this skill for ANY mention of agent loops, agentic pipelines, skill routing, skill-scoped tools, subagents, tool-calling with local models, or evaluation of agent outputs — even if the user just says "my agent keeps looping" or "how do I add tools to my local model". This skill is opinionated: it teaches battle-tested patterns and warns against known pitfalls with lightweight models.
---

# Agent Harness Skill

Opinionated guide for building production-grade **skill-based** multiagent harnesses on **lightweight local models** — Ollama, llama.cpp/LM Studio, and Hugging Face Transformers — in **Python and TypeScript**, using **raw custom loops** (no framework, no central orchestrator).

---

## Core Philosophy

Lightweight models are not GPT-4. They:
- Produce malformed JSON/tool calls frequently
- Struggle with long system prompts
- Hallucinate tool names and argument schemas
- Lose track of context in long loops

Your harness must **compensate for these weaknesses** at the infrastructure level, not the prompt level alone.

**The three laws of lightweight agent harnesses:**
1. **Never trust model output blindly** — always parse defensively
2. **Always evaluate before proceeding** — every loop tick has a pass/fail gate
3. **Build for recovery, not happy-path** — retries, fallbacks, and graceful termination are first-class

---

## Architecture Overview

Skills replace the orchestrator. The LLM selects a skill; the skill owns its agents, tools, and memory. Nothing is global.

```
+----------------+     +-------------------------------------------------------+
| Memory         |     |                        SKILLS                         |
| Manager        |---->|  +------------------------------------------------+   |
+----------------+     |  | Skill A         Skill B         Skill N        |   |
                        |  | |- agents/      |- agents/      |- agents/    |   |
       +-----+          |  | |- scripts.py   |- scripts.py   |- ...        |   |
       | LLM |--------->|  | |- skill.md     |- skill.md                   |   |
       +-----+          |  | +- skill_memory +- skill_memory               |   |
                        |  +---------------------+--------------------------+   |
                        +------------------------|-------------------------------+
                                                 | (selected skill activates)
                        +------------------------v------------------------------+
  +-----------+         |                    AGENT LOOP                        |
  | Tools     |-------->|  Input --> Model --> Parse --> Tool execution        |
  | (scoped   |         |               ^_________________________|            |
  | per skill)|         +-----------------------------------+-------------------+
  +-----------+                                             |
        ^               +-----------------------------------+------+
        |               |       Sandbox (safe exec, feeds back)   |
        +---------------|                                          |
                        +------------------------------------------+
                                                             |
                                          +------------------v-----------------+
                                          |         EVALS / Guardrail          |
                                          +------------------------------------+
```

**Key components:**
- **Memory Manager** — persists cross-session state; injected into LLM context at startup
- **LLM (Skill Router)** — reads available skill descriptors, selects the right skill for the task; no planner or router agent needed
- **Skills** — self-contained units; each owns its agents, scripts, a `skill.md`, and a private memory store
- **Agent Loop** — the inner loop each selected skill's agents run (see below)
- **Tools (skill-scoped)** — every skill declares only the tools it needs; the global tool registry is never exposed
- **Sandbox** — safe execution environment; results feed back into the agent loop
- **EVALS / Guardrail** — output gate; every result is checked before being returned to the caller

---

## Skill Structure

Each skill is a self-contained directory:

```
skills/
+-- my_skill/
    +-- skill.md          # Description + trigger criteria (loaded by LLM router)
    +-- skill_memory.json # Persistent state scoped to this skill
    +-- agents/
    |   +-- primary.py    # Main agent for this skill
    +-- scripts.py        # Scoped tools + deterministic helpers
```

**Rules:**
- Skills are loaded lazily — only the selected skill's files enter context
- `skill.md` must fit in <= 200 tokens (it is always read for routing decisions)
- `skill_memory.json` is read/written only by agents within that skill
- Agents inside a skill share a narrow context: task + skill_memory + their own tool subset

---

## Skill Routing (Replaces the Orchestrator)

The LLM itself acts as the router. Feed it a compact registry of skill descriptors and let it pick.

### Python

```python
import json, pathlib

SKILLS_DIR = pathlib.Path("skills")

def build_skill_registry() -> list[dict]:
    registry = []
    for skill_dir in SKILLS_DIR.iterdir():
        md = (skill_dir / "skill.md").read_text()
        header = _parse_frontmatter(md)   # extract YAML name + description
        registry.append({
            "name": header["name"],
            "description": header["description"],
            "path": str(skill_dir)
        })
    return registry

def route_skill(task: str, model_client, registry: list[dict]) -> dict | None:
    registry_text = "\n".join(
        f"- {s['name']}: {s['description']}" for s in registry
    )
    prompt = (
        f"Available skills:\n{registry_text}\n\n"
        f"Task: {task}\n\n"
        "Reply with ONLY the skill name that best matches this task. "
        "If no skill fits, reply 'none'."
    )
    raw = model_client.complete(
        system="You are a skill router. Reply with a single skill name.",
        messages=[{"role": "user", "content": prompt}]
    )
    chosen = raw.strip().lower()
    return next((s for s in registry if s["name"] == chosen), None)
```

### TypeScript

```typescript
async function routeSkill(
  task: string,
  client: ModelClient,
  registry: SkillEntry[]
): Promise<SkillEntry | null> {
  const registryText = registry.map(s => `- ${s.name}: ${s.description}`).join("\n");
  const raw = await client.complete({
    system: "You are a skill router. Reply with a single skill name.",
    messages: [{ role: "user", content:
      `Available skills:\n${registryText}\n\nTask: ${task}\n\nReply with ONLY the skill name. If none fit, reply "none".`
    }]
  });
  const chosen = raw.trim().toLowerCase();
  return registry.find(s => s.name === chosen) ?? null;
}
```

**Routing rules for small models:**
- Keep each skill description under 30 words in the registry
- Pass no more than 10 skills at once; group rarely-used skills into a meta-skill
- If routing returns `none` or an unknown name, retry once with a clarifying hint, then fall back to a default skill

---

## Skill-Scoped Tool Loading

Each skill declares its tools in `scripts.py`. The agent loop only receives that skill's tools — never the global set.

```python
# skills/web_researcher/scripts.py

TOOLS: dict[str, callable] = {}

def register(fn):
    TOOLS[fn.__name__] = fn
    return fn

@register
def web_search(query: str) -> str:
    """Search the web. Args: query (str)"""
    ...  # your implementation

@register
def fetch_page(url: str) -> str:
    """Fetch a URL. Args: url (str)"""
    ...

def get_tools() -> dict[str, callable]:
    return TOOLS
```

```python
# harness/runner.py — loading tools for the selected skill only
import importlib.util, pathlib

def load_skill_tools(skill_path: str) -> dict:
    scripts = pathlib.Path(skill_path) / "scripts.py"
    spec = importlib.util.spec_from_file_location("skill_scripts", scripts)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.get_tools()
```

**Tool-scoping rules:**
- A skill should expose <= 5 tools; more = split into two skills
- Tool names must not collide across skills (prefix with skill name if needed)
- Never pass a tool from Skill A to an agent running Skill B

---

## The Agent Loop

Every agent inside a skill runs this loop:

```
LOOP:
  1. Build context (skill.md + skill_memory + task + scoped tools)
  2. Call model
  3. Parse output (text | tool_call | final_answer)
  4. If tool_call -> execute in Sandbox -> append result -> GOTO 2
  5. EVALUATE output (see Evaluation Layer)
  6. If eval PASS -> return result to EVALS/Guardrail
  7. If eval FAIL + retries < MAX -> rewrite prompt -> GOTO 2
  8. If eval FAIL + retries exhausted -> escalate or return partial
```

### Python

```python
from dataclasses import dataclass
from typing import Any, Callable

@dataclass
class AgentLoop:
    model_client: Any
    tools: dict[str, Callable]      # skill-scoped only
    evaluator: "LoopEvaluator"
    system_prompt: str              # skill.md content
    skill_memory: dict              # mutable; persisted after loop
    max_iterations: int = 10
    max_retries: int = 3

    def run(self, task: str) -> dict:
        history = [{"role": "user", "content": task}]
        retries = 0

        for iteration in range(self.max_iterations):
            raw = self.model_client.complete(
                system=self.system_prompt,
                messages=history,
                tools=list(self.tools.keys()),
            )
            parsed = parse_output(raw)

            if parsed["type"] == "tool_call":
                result = sandbox_exec(self.tools, parsed)
                history.append({"role": "assistant", "content": raw})
                history.append({"role": "tool", "content": str(result)[:500]})
                continue

            if parsed["type"] == "final_answer":
                eval_result = self.evaluator.evaluate(task, parsed["content"], history)
                if eval_result.passed:
                    _update_skill_memory(self.skill_memory, task, parsed["content"])
                    return {"status": "ok", "result": parsed["content"], "iterations": iteration}
                if retries < self.max_retries:
                    retries += 1
                    history.append({"role": "user", "content": eval_result.retry_prompt})
                    continue
                return {"status": "partial", "result": parsed["content"], "reason": eval_result.reason}

        return {"status": "max_iterations", "history": history}
```

---

## Sandbox Execution

Tool calls run inside a sandbox — never directly. The sandbox catches exceptions, enforces timeouts, and truncates output before it re-enters the loop.

```python
import signal, contextlib

@contextlib.contextmanager
def _timeout(seconds: int):
    def handler(signum, frame): raise TimeoutError()
    signal.signal(signal.SIGALRM, handler)
    signal.alarm(seconds)
    try: yield
    finally: signal.alarm(0)

def sandbox_exec(tools: dict, parsed: dict, timeout_s: int = 10) -> str:
    fn = tools.get(parsed["tool"])
    if not fn:
        return f"ERROR: unknown tool '{parsed['tool']}'"
    try:
        with _timeout(timeout_s):
            result = fn(**parsed.get("args", {}))
            return str(result)[:500]
    except TimeoutError:
        return f"ERROR: tool '{parsed['tool']}' timed out after {timeout_s}s"
    except Exception as e:
        return f"ERROR: {e}"
```

---

## Skill Memory

```python
import json, pathlib

def load_skill_memory(skill_path: str) -> dict:
    p = pathlib.Path(skill_path) / "skill_memory.json"
    return json.loads(p.read_text()) if p.exists() else {}

def _update_skill_memory(memory: dict, task: str, result: str):
    memory.setdefault("history", []).append({"task": task, "result": result[-200:]})
    memory["history"] = memory["history"][-20:]   # cap at 20 entries

def save_skill_memory(skill_path: str, memory: dict):
    p = pathlib.Path(skill_path) / "skill_memory.json"
    p.write_text(json.dumps(memory, indent=2))
```

**Memory rules:**
- Never grow unbounded — keep last N entries (N <= 20)
- Store summaries only, never raw tool output
- Skill memory is private — agents in other skills cannot read it

---

## Tool Parsing (Critical for Lightweight Models)

```python
import json, re

def parse_output(raw: str) -> dict:
    cleaned = re.sub(r"```(?:json|tool_call)?\n?", "", raw).strip().rstrip("`")
    try:
        obj = json.loads(cleaned)
        if "tool" in obj:
            return {"type": "tool_call", "tool": obj["tool"], "args": obj.get("args", {})}
        if "answer" in obj or "result" in obj:
            return {"type": "final_answer", "content": obj.get("answer") or obj.get("result")}
    except json.JSONDecodeError:
        pass
    tool_match = re.search(r'"tool"\s*:\s*"(\w+)"', cleaned)
    if tool_match:
        args_match = re.search(r'"args"\s*:\s*(\{.*?\})', cleaned, re.DOTALL)
        args = {}
        if args_match:
            try: args = json.loads(args_match.group(1))
            except: pass
        return {"type": "tool_call", "tool": tool_match.group(1), "args": args}
    return {"type": "final_answer", "content": raw}
```

**Tool schema rules:** short snake_case names, max 3 args per tool, one-line description + example, embed as JSON in system prompt.

---

## Evaluation Layer (EVALS / Guardrail)

```python
from dataclasses import dataclass

@dataclass
class EvalResult:
    passed: bool
    score: float
    reason: str
    retry_prompt: str

class LoopEvaluator:
    def __init__(self, checks: list):
        self.checks = checks

    def evaluate(self, task, output, history) -> EvalResult:
        results = [c.run(task, output, history) for c in self.checks]
        score = sum(r.score for r in results) / len(results)
        failures = [r for r in results if not r.passed]
        if not failures:
            return EvalResult(True, score, "all checks passed", "")
        retry = "Your previous response had issues:\n" + \
                "\n".join(f"  - {f.reason}" for f in failures) + \
                "\nPlease try again addressing each issue."
        return EvalResult(False, score, "; ".join(f.reason for f in failures), retry)

class FormatCheck:
    def run(self, task, output, history):
        parsed = parse_output(output)
        ok = parsed["type"] != "unknown"
        return EvalResult(ok, 1.0 if ok else 0.0, "" if ok else "Output could not be parsed", "")

class LoopDetector:
    def run(self, task, output, history):
        msgs = [m["content"] for m in history if m["role"] == "assistant"]
        if len(msgs) >= 2 and msgs[-1] == msgs[-2]:
            return EvalResult(False, 0.0, "Agent stuck — identical consecutive outputs",
                              "Your last two responses were identical. Try a different approach.")
        return EvalResult(True, 1.0, "", "")

class ToolHallucinationCheck:
    def __init__(self, valid_tools: list[str]):
        self.valid_tools = valid_tools
    def run(self, task, output, history):
        parsed = parse_output(output)
        if parsed["type"] == "tool_call" and parsed["tool"] not in self.valid_tools:
            return EvalResult(False, 0.0,
                              f"Model called non-existent tool '{parsed['tool']}'",
                              f"Available tools are: {self.valid_tools}. Use only these.")
        return EvalResult(True, 1.0, "", "")
```

---

## Full Session Runner

```python
import pathlib

def run_session(task: str, model_client, skills_dir="skills"):
    registry = build_skill_registry()
    skill = route_skill(task, model_client, registry)
    if not skill:
        return {"error": "No matching skill found for this task."}

    tools = load_skill_tools(skill["path"])
    skill_memory = load_skill_memory(skill["path"])
    system_prompt = (pathlib.Path(skill["path"]) / "skill.md").read_text()

    evaluator = LoopEvaluator([
        FormatCheck(),
        LoopDetector(),
        ToolHallucinationCheck(list(tools.keys())),
    ])

    loop = AgentLoop(
        model_client=model_client,
        tools=tools,
        evaluator=evaluator,
        system_prompt=system_prompt,
        skill_memory=skill_memory,
    )
    result = loop.run(task)

    if result["status"] == "ok":
        save_skill_memory(skill["path"], skill_memory)

    return result
```

---

## Best Practices Checklist

- [ ] Each skill exposes <= 5 scoped tools — no global tool registry
- [ ] Skill descriptions in registry are <= 30 words
- [ ] Loop has hard `max_iterations` cap (<= 15)
- [ ] Loop has `max_retries` cap separate from iterations (<= 3)
- [ ] Every tool call runs through `sandbox_exec`, never raw
- [ ] Tool output truncated to <= 500 chars before history append
- [ ] `LoopDetector` always active
- [ ] `ToolHallucinationCheck` always active when tools are present
- [ ] Skill system prompt under 500 tokens for models < 7B params
- [ ] `skill_memory.json` bounded (<= 20 entries), stores summaries only
- [ ] Routing fallback exists for `none` / unknown skill names
- [ ] Eval scores logged per iteration for debugging

---

## Debugging a Stuck/Flaky Harness

| Symptom | Likely cause | Fix |
|---|---|---|
| Wrong skill selected | Descriptions too similar or too long | Shorten and differentiate registry descriptions |
| Agent loops forever | No `LoopDetector`, missing termination signal | Add `LoopDetector` + "reply FINAL:" instruction |
| Malformed tool calls | Model not following schema | Add `FormatCheck`, simplify schema |
| Tool hallucination | Global tools leaking in | Confirm only scoped tools passed; add `ToolHallucinationCheck` |
| Context window overflow | History grows unbounded | Keep system + last N turns only |
| Sandbox timeout | Tool doing uncapped I/O | Lower `timeout_s`; add retry with backoff |
| Skill memory bloat | Storing raw results | Store summaries; enforce entry cap |

---

## Reference Files

- `references/model-clients.md` — Full adapter code for Ollama, llama.cpp/LM Studio, and HuggingFace Transformers