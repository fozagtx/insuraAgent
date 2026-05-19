# Insurance Appeal Agent

**JacHacks Spring 2026 - Consumer Healthcare track**

An agentic AI that reads a health-insurance denial letter and the patient's
policy document and autonomously drafts a personalized, citation-backed
appeal letter. Written in [Jac](https://docs.jaseci.org/) with byLLM.

> One in seven privately-insured U.S. claims is denied. Most are never
> appealed because writing a competent appeal letter takes hours of
> reading policy fine print and matching it against the denial reason
> line-by-line. This agent does it in about a minute.

---

## What it does

Given three text inputs - the **denial letter**, the **policy document**,
and the patient's **clinical record** - the agent:

1. **Classifies** the denial reason into a structured category
   (`NOT_MEDICALLY_NECESSARY`, `OUT_OF_NETWORK`, `PRIOR_AUTH_MISSING`,
   `EXPERIMENTAL_OR_INVESTIGATIONAL`, `CODING_ERROR`,
   `BENEFIT_EXCLUSION`, `OTHER`).
2. **Extracts** every policy clause relevant to that denial reason, with
   verbatim quotes and section numbers.
3. **Finds contradictions** between the denial and the policy, anchored
   in the clinical record (e.g. "denial says HSAT was not attempted;
   policy §7.2(i) waives HSAT for NYHA Class III CHF; chart confirms
   NYHA Class III").
4. **Drafts** a formal first-level internal appeal letter with a subject
   line, structured body, and citation list.
5. **Persists** every Claim, Policy, and Appeal node on the Jac `root`
   graph so they survive across sessions.

## What's agentic about it

The orchestrator (`orchestrator.jac::plan_and_generate_appeal`) is a
single LLM-typed function with **five tools registered** via
`by llm(tools=[...])`. The LLM decides on its own which tool to call
first, what to feed back into the next call, and when it has enough
information to produce the final `AppealLetter`. No hand-written
`if/elif/then` pipeline - byLLM runs the full ReAct loop under the
hood. This is what the REST walker (`/walker/submit_claim`) exposes.

A judge can grep `orchestrator.jac` for `tools=[` to see the agentic
surface in one line.

The **CLI demo (`main.jac`)** calls the same five tools **sequentially**
rather than going through the ReAct loop. The reason is purely
practical: byLLM's tool-calling ReAct loop currently hangs on
Featherless's vLLM tool-call layer for multi-turn calls, and a
~80-second sequential demo is more reliable to show on stage than a
multi-minute agentic loop that may stall. The tools, prompts, outputs,
and persisted graph are identical either way.

## Track

**Consumer Healthcare** ($600 first prize) - denied health-insurance
claims are a massive consumer-healthcare pain point: average appeal
takes 5–10 hours of unpaid patient work and most people simply give up.

---

## Architecture quick map

| File | Role |
|---|---|
| `models.jac` | `node` types (Claim, Policy, Appeal), enums (DenialReason, AppealStrength), structured value objects (PolicyClause, Contradiction, AppealLetter). |
| `tools.jac` | The 5 LLM-typed tools - `extract_denial_reason`, `extract_relevant_clauses`, `find_contradictions`, `assess_appeal_strength`, `draft_appeal_letter`. |
| `orchestrator.jac` | The agentic core - one `by llm(tools=[...])` call that lets the LLM plan and dispatch the five tools. |
| `main.jac` | CLI demo. Calls the five tools **sequentially** for a fast, reliable on-stage demo (~80s wall-clock). |
| `walkers.jac` | REST surface - `submit_claim` and `list_appeals` walkers. `submit_claim` calls the **agentic orchestrator**, not the sequential path. |
| `app.jac` + `frontend.cl.jac` | Single-file Jac-native React UI mounted on the same server. |
| `web/index.html` | Optional static drag-and-drop UI that talks to the REST endpoints. |

---

## Install

```bash
# 1. Clone / cd into this folder
cd insurance-appeal-agent

# 2. Create a venv (Python 3.11+ recommended; tested on 3.14)
python3 -m venv .venv
source .venv/bin/activate

# 3. Install Jac + byLLM
pip install jaseci byllm

# 4. Verify
jac --version
```

## Set an API key

This project runs on **[Featherless.AI](https://featherless.ai)** by default
- a serverless inference platform for open-weight models. Get a key at
https://featherless.ai/account/api-keys.

```bash
export FEATHERLESS_API_KEY=fl-...
```

`jac.toml` ships pointing at **`openai/Qwen/Qwen2.5-14B-Instruct`**
routed through Featherless's OpenAI-compatible endpoint. We dropped
from 72B to 14B because 72B was repeatedly hitting Featherless
capacity errors during the hackathon window; 14B handles the
structured-output workload reliably and is noticeably faster.

`run_demo.sh` re-exports `OPENAI_API_KEY` / `OPENAI_API_BASE` from
your Featherless key so LiteLLM routes the `openai/...` model id
correctly. If you launch `jac run` by hand, do the same:

```bash
export OPENAI_API_KEY="$FEATHERLESS_API_KEY"
export OPENAI_API_BASE="https://api.featherless.ai/v1"
```

> **First time on Featherless?** Run the 60-second compatibility probe
> first - it confirms typed-object schemas round-trip on your chosen
> model before you fire the full agent:
>
> ```bash
> jac run probe_featherless.jac
> ```
>
> If the third (typed-obj) step fails, see `FEATHERLESS_COMPAT.md` for
> the patch we applied.

### Featherless quirks worth knowing

Two of the five tools (`extract_denial_reason` and
`assess_appeal_strength`) originally returned enum types directly.
Featherless's vLLM backend rejects byLLM's `response_format:
json_schema` envelope on both typed objects **and** enums, so those
two tools now ask the LLM for a `str` and match it against the enum
on the Python side. Public signatures and outputs are unchanged.

### Swap models

Any [LiteLLM-compatible model](https://docs.litellm.ai/docs/providers) works.
Edit `default_model` in `jac.toml`:

```toml
[plugins.byllm.model]
# Default (Featherless via OpenAI-compat):
default_model = "openai/Qwen/Qwen2.5-14B-Instruct"
# default_model = "openai/Qwen/Qwen2.5-72B-Instruct"        # if capacity allows
# default_model = "openai/mistralai/Mistral-Large-Instruct-2407"

# Other providers (use their own API key, drop the OPENAI_API_BASE override):
# default_model = "claude-sonnet-4-20250514"                # ANTHROPIC_API_KEY
# default_model = "gemini/gemini-2.0-flash"                 # GEMINI_API_KEY
# default_model = "openai/gpt-4o-mini"                      # OPENAI_API_KEY
```

---

## Run the CLI demo

End-to-end on the bundled sample claim:

```bash
./run_demo.sh
# or, with your env already exported:
jac run main.jac
```

You'll see the sample claim summary, then each of the five tools run
in order with per-step timing, then the generated appeal letter, the
citations list, and confirmation that the Appeal node was persisted
on the root graph. Expect roughly 80 seconds total wall-clock for
all five tool calls on the default Qwen 14B backend.

## Run as a REST server

```bash
jac start app.jac --port 8001
```

Port 8001 is deliberate - the default 8000 collides with a sibling
project on the same machine; override with `--port` if you don't have
that conflict. `app.jac` brings in `walkers.jac` so both endpoints
are mounted on the same server alongside the Jac-native React UI.

Two walker endpoints come up:

### `POST /walker/submit_claim`

Runs the **agentic orchestrator** (the `by llm(tools=[...])` call -
LLM picks tool order), persists Claim / Policy / Appeal nodes, and
returns the drafted letter.

```bash
curl -X POST http://localhost:8001/walker/submit_claim \
  -H 'Content-Type: application/json' \
  -d @- <<'JSON'
{
  "patient_name": "Jordan A. Reyes",
  "member_id": "BSH-44892-01",
  "claim_number": "CLM-2026-0418-9921",
  "date_of_service": "2026-04-18",
  "cpt_code": "95810",
  "billed_amount": 3847.00,
  "plan_name": "BlueShield PPO Gold 2026",
  "denial_text": "...full denial letter text...",
  "policy_text": "...full policy text...",
  "clinical_record": "...clinical summary..."
}
JSON
```

Response:

```json
{
  "appeal_id": "APL-...",
  "claim_id": "CLM-2026-0418-9921",
  "subject": "Formal Appeal - Claim CLM-2026-0418-9921 ...",
  "letter": "Dear Appeals Department, ...",
  "citations": ["Plan Section 7.2(i)", "..."]
}
```

### `POST /walker/list_appeals`

```bash
curl -X POST http://localhost:8001/walker/list_appeals \
  -H 'Content-Type: application/json' -d '{}'
```

Returns every Appeal persisted on the root graph.

## Run the web UI (optional)

After starting the server with `jac start app.jac --port 8001`, open
`web/index.html` directly in a browser. Click **Load sample claim**,
then **Generate appeal**.

The page is a single static HTML file - no build step, no Node.

> Depending on your browser's CORS policy you may need to serve `web/`
> with a static server (`python3 -m http.server -d web 5500`) rather
> than opening the file directly. Update the API base URL in
> `index.html` if you used a port other than 8001.

---

## Sample input/output

Input lives in `samples/`:

- `samples/denial_001.txt` - a fictional BlueShield denial for an
  in-lab sleep study (CPT 95810), reason: "HSAT not attempted first."
- `samples/policy_001.txt` - the relevant PPO Gold plan section that
  **waives** the HSAT-first requirement when the patient has NYHA
  Class III CHF or is on chronic opioids.
- `samples/patient_record_001.txt` - clinical note documenting the
  patient has *both* conditions.

The agent connects all three: the denial is wrong because the policy's
own §7.2(i) carves out exactly this patient's situation. The generated
appeal quotes the policy back to the insurer.

---

## Jac features the project uses

| Jac feature | Where | Why |
|---|---|---|
| `node` types with auto-persistence on `root` | `models.jac` | Claim / Policy / Appeal survive across runs |
| `enum` types as LLM return values | `models.jac` `DenialReason`, `AppealStrength` | Constrains LLM output to schema-valid categories (Python-side match for Featherless compat) |
| `obj` types as LLM return values | `models.jac` `PolicyClause`, `Contradiction`, `AppealLetter` | Forces structured output instead of free-form text |
| `def foo(...) -> T by llm()` | `tools.jac` | Every tool is one line - no JSON-parsing boilerplate |
| `def foo(...) -> T by llm(tools=[...])` | `orchestrator.jac` | The agentic call - LLM picks tool order |
| `walker:pub ... { has ...; can run with Root entry { ... } }` | `walkers.jac` | Becomes a public REST endpoint |
| `here ++> Node(...)` | `walkers.jac`, `main.jac` | Persistent graph edges from root |
| `[-->[?:Appeal]]` filtered traversal | `walkers.jac` `list_appeals` | Type-safe graph query |
| Docstring-as-prompt | `tools.jac` (every tool) | The docstring above each `by llm()` def becomes the system prompt |

---

## Project layout

```
insurance-appeal-agent/
├── jac.toml              # byLLM model config (Qwen2.5-14B via Featherless)
├── models.jac            # nodes, enums, structured value objects
├── tools.jac             # 5 LLM-typed tools
├── orchestrator.jac      # 1 agentic `by llm(tools=[...])` call
├── walkers.jac           # REST endpoints (submit_claim, list_appeals)
├── app.jac               # server entry - mounts walkers + Jac React UI
├── frontend.cl.jac       # Jac-native React frontend (single file)
├── main.jac              # CLI demo (sequential tool pipeline)
├── probe_featherless.jac # 60-second backend compatibility check
├── smoke_llm.jac         # 10-line byLLM connectivity check
├── run_demo.sh           # env-var wrapper for the CLI demo
├── samples/
│   ├── denial_001.txt
│   ├── policy_001.txt
│   └── patient_record_001.txt
├── web/index.html        # static drag-and-drop UI
└── README.md
```

## Disclaimer

This tool is a hackathon prototype. The sample data is **fictional**
(names, member IDs, claim numbers, providers - all invented). The
generated appeal letter is **not legal advice**. Real appeals should be
reviewed by a human (patient advocate, attorney, or the patient
themselves) before submission. Different plans have different appeal
procedures; always follow your specific plan's instructions.

## Single-file full-stack (Jac client)

For the **Best Use of Jac** prize criterion that rewards *single-file
full-stack development*, this project also ships a Jac-native React
frontend:

```bash
jac start app.jac --port 8001
```

Then open the printed URL. The UI lives in `frontend.cl.jac` (one
file, React JSX inline) and spawns the same `submit_claim` /
`list_appeals` walkers via Jac's in-browser `root spawn` runtime - no
hand-rolled `fetch()`, no separate JS build pipeline, no REST glue.
The whole stack (data model · agentic orchestrator · walker API ·
React UI) is `.jac` files. Click *Load sample claim* → *Generate
appeal* for a one-click demo.
