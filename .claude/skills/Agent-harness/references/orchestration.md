# Skill-Scoped Agent Patterns

Reference for multi-agent patterns *within* a single skill. There is no global orchestrator. The LLM routes to a skill; everything below happens inside that skill's boundary.

---

## Pattern 1: Primary + Critic (most common)

The primary agent produces a result; the critic agent validates it before it hits the guardrail.

```python
# skills/my_skill/agents/primary.py
def run(task, tools, skill_memory, model_client) -> str:
    loop = AgentLoop(model_client, tools, build_evaluator(tools), skill_memory=skill_memory)
    return loop.run(task)

# skills/my_skill/agents/critic.py
def critique(task, candidate, model_client) -> dict:
    prompt = (
        f"Task: {task}\n"
        f"Candidate answer:\n{candidate}\n\n"
        "Identify any factual errors, missing steps, or policy violations. "
        "Reply with JSON: {\"ok\": true} or {\"ok\": false, \"issues\": [\"...\"]}"
    )
    raw = model_client.complete(system="You are a strict critic.", messages=[{"role":"user","content":prompt}])
    try:
        return json.loads(raw)
    except Exception:
        return {"ok": True}   # parse failure = assume ok, do not block

# skills/my_skill/runner.py
def run(task, model_client, tools, skill_memory):
    result = primary.run(task, tools, skill_memory, model_client)
    verdict = critic.critique(task, result, model_client)
    if not verdict.get("ok"):
        # retry primary with critic feedback injected
        enriched = task + "\n\nPrevious attempt issues:\n" + "\n".join(verdict["issues"])
        result = primary.run(enriched, tools, skill_memory, model_client)
    return result
```

---

## Pattern 2: Sequential Pipeline

Agents inside a skill run in a fixed sequence; each passes its output to the next. Use when the task has clear, ordered stages.

```python
def run_pipeline(task, stages: list[callable], tools, model_client) -> str:
    context = task
    for stage_fn in stages:
        context = stage_fn(context, tools, model_client)
    return context

# Example: research -> summarise -> format
result = run_pipeline(task, [research_agent, summarise_agent, format_agent], tools, client)
```

**Rules:**
- Each stage receives only the output of the previous stage, not the full history
- Keep each stage's system prompt under 300 tokens for small models
- If a stage fails, retry that stage alone — do not restart the pipeline

---

## Pattern 3: Parallel Fan-out (use sparingly)

Split independent subtasks across multiple agents, then merge. Only worth the complexity if the subtasks are genuinely independent.

```python
import concurrent.futures

def fan_out(subtasks: list[str], agent_fn: callable, tools, model_client) -> list[str]:
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        futures = {ex.submit(agent_fn, t, tools, model_client): t for t in subtasks}
        results = []
        for f in concurrent.futures.as_completed(futures):
            try:
                results.append(f.result())
            except Exception as e:
                results.append(f"ERROR: {e}")
    return results

def merge(results: list[str], model_client) -> str:
    combined = "\n\n".join(f"Result {i+1}:\n{r}" for i, r in enumerate(results))
    raw = model_client.complete(
        system="Merge and deduplicate these results into one coherent answer.",
        messages=[{"role": "user", "content": combined}]
    )
    return raw
```

**Warning:** fan-out multiplies token usage and failure surface. Prefer sequential unless you have a clear latency reason to parallelize.

---

## Spawning Rules (all patterns)

- Keep each agent's system prompt under 400 tokens for models < 13B
- Each agent has a **single, narrow role** — no "do everything" agents
- Pass only the relevant context slice to each agent, not the full session history
- Agents within a skill share `skill_memory` but must not write to each other's local state
- Never spawn more than 4 concurrent agents for small models — context contention degrades quality fast