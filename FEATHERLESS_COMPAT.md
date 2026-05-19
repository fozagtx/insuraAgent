# Featherless Compatibility Notes

## The risk (3 sentences)

byLLM emits OpenAI-style `response_format: {"type": "json_schema", ...}`
whenever a `def ... -> X by llm()` returns a typed `obj` or `list[obj]`.
Some vLLM-backed Featherless models accept this only partially (or reject
it outright on the more aggressive schemas), and a sibling project hit
exactly that failure mode. This project's tools (`tools.jac`) and the
agentic orchestrator (`orchestrator.jac`) lean heavily on typed-obj
returns, so we need a 60-second probe before the demo and a 5-minute
fallback patch ready to apply if the probe fails.

## Exposed surface (what's at risk)

| Function | Return type | Risk |
|---|---|---|
| `extract_denial_reason` | `DenialReason` (enum) | LOW — enums round-trip fine |
| `extract_relevant_clauses` | `list[PolicyClause]` | **HIGH** — list of typed objs |
| `find_contradictions` | `list[Contradiction]` | **HIGH** — list of typed objs |
| `assess_appeal_strength` | `AppealStrength` (enum) | LOW |
| `draft_appeal_letter` | `AppealLetter` | **HIGH** — typed obj |
| `plan_and_generate_appeal` | `AppealLetter` | **HIGH** — agentic + typed obj |

Three of five tools plus the orchestrator return typed objects.

## How to run the probe

```bash
export FEATHERLESS_API_KEY=fl-...           # get one at featherless.ai/account/api-keys
jac run probe_featherless.jac
```

It tries 3 calls of increasing schema complexity (str → enum → typed obj)
and tells you which step fails.

## Decision tree

```
Probe result
│
├── All 3 pass        →  Ship it. Run `jac run main.jac` — no changes needed.
│
├── 1+2 pass, 3 fails →  Either:
│                        (a) try a stronger model first (1-line change):
│                              export FEATHERLESS_PROBE_MODEL=featherless_ai/Qwen/Qwen2.5-72B-Instruct
│                            then re-probe;
│                        (b) if that still fails, apply the patch below.
│
└── 1 fails           →  Not a schema problem. Check API key, base URL,
                         and that the model name is spelled correctly.
                         Fall back to ANTHROPIC_API_KEY for the demo:
                              unset FEATHERLESS_API_KEY
                              export ANTHROPIC_API_KEY=sk-ant-...
                              # edit jac.toml: default_model = "claude-sonnet-4-20250514"
```

## The 5-minute fallback patch

If step 3 of the probe fails, the fix is to switch the typed-obj
returns to JSON-encoded `str` returns and parse them in Python.
This is the same pattern the sibling project uses.

### 1. Add a JSON-parse helper to `tools.jac`

Insert at the top of the file (after imports, before
`glob llm = ...`):

```jac
import json;
import re;

# Best-effort extraction of a JSON object from a model reply.
# Models sometimes wrap JSON in prose or markdown fences; this strips that.
def _parse_json_obj(s: str) -> dict {
    if not s { return {} ; }
    txt = s.strip();
    m = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", txt, re.DOTALL);
    if m {
        txt = m.group(1);
    } else {
        start = txt.find("{");
        if start == -1 { return {} ; }
        depth = 0; end = -1; i = start;
        while i < len(txt) {
            ch = txt[i];
            if ch == "{" { depth += 1; }
            elif ch == "}" {
                depth -= 1;
                if depth == 0 { end = i; break; }
            }
            i += 1;
        }
        if end == -1 { return {} ; }
        txt = txt[start:end+1];
    }
    try { return json.loads(txt); }
    except Exception as e { return {} ; }
}

def _parse_json_list(s: str) -> list {
    if not s { return [] ; }
    txt = s.strip();
    m = re.search(r"```(?:json)?\s*(\[.*?\])\s*```", txt, re.DOTALL);
    if m { txt = m.group(1); }
    else {
        start = txt.find("[");
        if start == -1 { return [] ; }
        depth = 0; end = -1; i = start;
        while i < len(txt) {
            ch = txt[i];
            if ch == "[" { depth += 1; }
            elif ch == "]" {
                depth -= 1;
                if depth == 0 { end = i; break; }
            }
            i += 1;
        }
        if end == -1 { return [] ; }
        txt = txt[start:end+1];
    }
    try { return json.loads(txt); }
    except Exception as e { return [] ; }
}
```

### 2. Replace the 3 high-risk tool signatures

Change `tools.jac` — only the **signatures and docstrings** of the three
HIGH-risk tools change. Enum tools stay as-is.

```jac
# extract_relevant_clauses: list[PolicyClause] -> str
"""
... (same prose) ... Return a JSON array (no markdown fence). Each
element must be an object with keys: section (str), title (str),
text (str), relevance_note (str). Return AT MOST 6 elements, ranked
by relevance. Return ONLY the JSON array.
"""
def extract_relevant_clauses_raw(
    policy_text: str,
    denial_reason: DenialReason
) -> str by llm();

def extract_relevant_clauses(
    policy_text: str,
    denial_reason: DenialReason
) -> list[PolicyClause] {
    raw = extract_relevant_clauses_raw(policy_text, denial_reason);
    out = [];
    for d in _parse_json_list(raw) {
        out.append(PolicyClause(
            section=str(d.get("section", "")),
            title=str(d.get("title", "")),
            text=str(d.get("text", "")),
            relevance_note=str(d.get("relevance_note", ""))
        ));
    }
    return out;
}

# find_contradictions: list[Contradiction] -> str
"""
... (same prose) ... Return a JSON array. Each element: denial_quote
(str), policy_quote (str), clause_section (str), explanation (str).
If no contradictions exist, return []. Return ONLY the JSON array.
"""
def find_contradictions_raw(
    denial_text: str,
    clinical_record: str,
    clauses: list[PolicyClause]
) -> str by llm();

def find_contradictions(
    denial_text: str,
    clinical_record: str,
    clauses: list[PolicyClause]
) -> list[Contradiction] {
    raw = find_contradictions_raw(denial_text, clinical_record, clauses);
    out = [];
    for d in _parse_json_list(raw) {
        out.append(Contradiction(
            denial_quote=str(d.get("denial_quote", "")),
            policy_quote=str(d.get("policy_quote", "")),
            clause_section=str(d.get("clause_section", "")),
            explanation=str(d.get("explanation", ""))
        ));
    }
    return out;
}

# draft_appeal_letter: AppealLetter -> str
"""
... (same prose) ... Return a JSON object with keys: subject (str),
salutation (str), body (str), citations (list of str), closing (str).
Return ONLY the JSON object.
"""
def draft_appeal_letter_raw(
    patient_name: str, member_id: str, claim_number: str,
    date_of_service: str, cpt_code: str, billed_amount: float,
    plan_name: str, denial_reason: DenialReason,
    contradictions: list[Contradiction], clinical_record: str
) -> str by llm();

def draft_appeal_letter(
    patient_name: str, member_id: str, claim_number: str,
    date_of_service: str, cpt_code: str, billed_amount: float,
    plan_name: str, denial_reason: DenialReason,
    contradictions: list[Contradiction], clinical_record: str
) -> AppealLetter {
    raw = draft_appeal_letter_raw(
        patient_name, member_id, claim_number, date_of_service,
        cpt_code, billed_amount, plan_name, denial_reason,
        contradictions, clinical_record
    );
    d = _parse_json_obj(raw);
    cites = d.get("citations") or [];
    if not isinstance(cites, list) { cites = [str(cites)]; }
    return AppealLetter(
        subject=str(d.get("subject", "")),
        salutation=str(d.get("salutation", "")),
        body=str(d.get("body", "")),
        citations=[str(c) for c in cites],
        closing=str(d.get("closing", ""))
    );
}
```

### 3. Make the orchestrator return `str`, then re-hydrate

In `orchestrator.jac`, change `plan_and_generate_appeal` to return `str`
and add a thin wrapper that re-hydrates the `AppealLetter`. Update its
docstring to say "Return ONLY the JSON object with fields: subject,
salutation, body, citations, closing." The walker / main only need to
call the wrapper — no other changes downstream.

```jac
def plan_and_generate_appeal_raw(
    denial_text: str, policy_text: str, clinical_record: str,
    patient_name: str, member_id: str, claim_number: str,
    date_of_service: str, cpt_code: str, billed_amount: float,
    plan_name: str
) -> str by agent_llm(
    tools=[extract_denial_reason, extract_relevant_clauses,
           find_contradictions, assess_appeal_strength,
           draft_appeal_letter]
);

def plan_and_generate_appeal(
    denial_text: str, policy_text: str, clinical_record: str,
    patient_name: str, member_id: str, claim_number: str,
    date_of_service: str, cpt_code: str, billed_amount: float,
    plan_name: str
) -> AppealLetter {
    import from tools { _parse_json_obj }
    raw = plan_and_generate_appeal_raw(
        denial_text, policy_text, clinical_record, patient_name,
        member_id, claim_number, date_of_service, cpt_code,
        billed_amount, plan_name
    );
    d = _parse_json_obj(raw);
    cites = d.get("citations") or [];
    if not isinstance(cites, list) { cites = [str(cites)]; }
    return AppealLetter(
        subject=str(d.get("subject", "")),
        salutation=str(d.get("salutation", "")),
        body=str(d.get("body", "")),
        citations=[str(c) for c in cites],
        closing=str(d.get("closing", ""))
    );
}
```

### 4. No changes needed in `walkers.jac`, `main.jac`, or `models.jac`

Because `plan_and_generate_appeal` still returns `AppealLetter`, the
walker and CLI code keep working unchanged. The `obj` types stay in
`models.jac` — they just stop being used as direct LLM return types.

---

## Env var alignment

This project accepts **`FEATHERLESS_API_KEY`** (matching the sibling
Subscription Killer project). LiteLLM also accepts the older
`FEATHERLESS_AI_API_KEY` name natively, so either works, but the
README and demo script now standardise on `FEATHERLESS_API_KEY` so
you only have to set one env var across both projects.
