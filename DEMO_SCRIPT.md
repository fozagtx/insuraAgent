# Demo Script — Insurance Appeal Agent (3 minutes)

Target: 2 min 45 s, leaving a 15 s buffer for transitions.

---

## 0:00 – 0:20 — The hook

**On camera (you, talking head, or voiceover over a stock b-roll of a
hospital bill):**

> One in seven privately-insured U.S. health-insurance claims gets
> denied. Most of those denials are never appealed — not because they're
> correct, but because writing a good appeal takes hours of policy
> reading. So people just pay the bill. I built an agent that does it
> in under a minute.

**Cut to:** terminal window, clean, ready to type.

---

## 0:20 – 1:00 — The inputs

**On screen:** `cat samples/denial_001.txt` — scroll through the denial
letter slowly enough to read the key line ("HSAT was not attempted and
failed prior to the in-lab study").

**Voiceover:**

> Here's a real-style denial: BlueShield refused to pay $3,800 for a
> sleep study because the patient supposedly didn't try the home test
> first. That's their reasoning.

**On screen:** `cat samples/policy_001.txt` — scroll to §7.2(i). Pause
briefly on the line: *"...moderate-to-severe pulmonary disease, congestive
heart failure (NYHA Class III or IV), neuromuscular disease, or chronic
opioid use."*

**Voiceover:**

> But here's the patient's own policy — section 7.2(i) says the home
> test is **waived** for patients with NYHA Class III heart failure or
> chronic opioid use. And the patient's chart shows they have both.

**On screen:** `cat samples/patient_record_001.txt` — quickly.

> The insurer denied a claim that their own policy explicitly covers.
> The patient just needs someone to make that argument in writing.

---

## 1:00 – 2:30 — The agent runs

**On screen:** terminal.

```bash
export FEATHERLESS_API_KEY=fl-...
jac run main.jac
```

**Voiceover, as the agent runs:**

> Watch what happens. This is one line of code:
> `def plan_and_generate_appeal(...) -> AppealLetter by llm(tools=[...])`.
> The agent has five tools — classify the denial, extract relevant
> clauses, find contradictions, assess strength, draft the letter — and
> it picks the order itself. No hard-coded pipeline.

**Highlight on screen:** open `orchestrator.jac` in a split pane and
draw attention to lines 47–55 (`tools=[ extract_denial_reason,
extract_relevant_clauses, find_contradictions, assess_appeal_strength,
draft_appeal_letter ]`).

**Cut back to:** terminal output.

> It's classified the denial as "not medically necessary." Now it's
> pulling the relevant policy clauses... finding the contradictions...
> assessing the appeal strength... and drafting.

**On screen:** the generated appeal letter scrolls in. Pause on the
**Citations** section.

**Voiceover:**

> Done. There's the appeal letter — subject line, formal salutation,
> body that quotes the denial language, quotes policy §7.2(i) back at
> them, references the patient's clinical record by date, and asks for
> reversal under the plan's 30-day appeal-decision window. With citations.

**Highlight:** the "PERSISTED ON GRAPH" block.

> And because this is built in Jac, the Claim, Policy, and Appeal nodes
> are all persisted on the root graph automatically — survive across
> sessions, queryable, no Postgres setup.

---

## 2:30 – 3:00 — What's next

**On camera:**

> Three things I'd add next:
>
> 1. **PDF ingestion** — most denials and policies arrive as PDFs.
>    Plug in a parser and the agent works on raw documents.
> 2. **Precedent lookup tool** — give the agent a sixth tool that
>    searches case law and state insurance commissioner rulings to
>    strengthen citations.
> 3. **Mail merge & e-filing** — most insurers now accept appeals
>    through a member portal. Automate the submission too.
>
> Code is open source. Built in Jac for JacHacks Spring 2026 —
> Consumer Healthcare track. Thanks for watching.

---

## Recording checklist

- [ ] Run `jac run main.jac` once before recording to warm the cache
      (first run is slower because of byllm compilation).
- [ ] Pre-set terminal font to ~18 pt, dark theme, wide enough that
      letter body doesn't wrap weirdly.
- [ ] Make sure `FEATHERLESS_API_KEY` is set in the recording session.
- [ ] Run `jac run probe_featherless.jac` once before recording to
      confirm the chosen Featherless model accepts typed-obj schemas
      (avoids a mid-recording surprise — see `FEATHERLESS_COMPAT.md`).
- [ ] Mention "powered by Featherless.AI" once on camera (sponsor prize hook).
- [ ] Have `orchestrator.jac` open in a second pane with line 23
      visible (`def plan_and_generate_appeal(...) -> AppealLetter by agent_llm(tools=[...])`).
- [ ] Test audio levels on the first 5 seconds before doing a full take.
- [ ] Mention "fictional sample data" once on camera so judges know it
      isn't real PII.
