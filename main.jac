# main.jac — end-to-end CLI demo.
#
#   jac run main.jac
#
# Reads the sample denial letter, policy document, and clinical record
# from samples/, lets the agent plan and execute the appeal, and prints
# the resulting letter. Requires ANTHROPIC_API_KEY or GEMINI_API_KEY.

import os;
import json;
import uuid;
import datetime;

import from models { Claim, Policy, Appeal, DenialReason, AppealStrength }
import from orchestrator { plan_and_generate_appeal }


def _read(path: str) -> str {
    with open(path, "r") as f {
        return f.read();
    }
}


def _check_keys() -> bool {
    have_featherless = (os.environ.get("FEATHERLESS_API_KEY", "") != ""
                        or os.environ.get("FEATHERLESS_AI_API_KEY", "") != "");
    have_anthropic   = os.environ.get("ANTHROPIC_API_KEY", "") != "";
    have_gemini      = os.environ.get("GEMINI_API_KEY", "") != "";
    have_openai      = os.environ.get("OPENAI_API_KEY", "") != "";
    if not (have_featherless or have_anthropic or have_gemini or have_openai) {
        print("=" * 72);
        print("ERROR: No LLM API key found in environment.");
        print("");
        print("  Pick one (Featherless is the default per jac.toml):");
        print("    export FEATHERLESS_API_KEY=fl-...      # default model");
        print("    export ANTHROPIC_API_KEY=sk-ant-...    # set jac.toml to");
        print("                                           # claude-sonnet-4-20250514");
        print("    export GEMINI_API_KEY=...              # set jac.toml to");
        print("                                           # gemini/gemini-2.0-flash");
        print("");
        print("  First time on Featherless? Run the probe first:");
        print("    jac run probe_featherless.jac");
        print("=" * 72);
        return False;
    }
    return True;
}


def _banner(title: str) {
    print("");
    print("=" * 72);
    print(title);
    print("=" * 72);
}


with entry {
    if not _check_keys() {
        # exit cleanly
    } else {
        # ---- 1. Load sample inputs ------------------------------------
        denial_text     = _read("samples/denial_001.txt");
        policy_text     = _read("samples/policy_001.txt");
        clinical_record = _read("samples/patient_record_001.txt");

        _banner("INSURANCE APPEAL AGENT — CLI DEMO");
        print("Sample claim:        CLM-2026-0418-9921");
        print("CPT code:            95810 (in-lab polysomnography)");
        print("Billed amount:       $3,847.00");
        print("Plan:                BlueShield PPO Gold 2026");
        print("Denial reason given: Not medically necessary");
        print("");
        print("Handing off to the agent. It will plan its own tool order...");

        # ---- 2. Persist the Claim + Policy on the root graph ----------
        claim = Claim(
            claim_id="CLM-2026-0418-9921",
            patient_name="Jordan A. Reyes",
            member_id="BSH-44892-01",
            cpt_code="95810",
            date_of_service="2026-04-18",
            billed_amount=3847.00,
            denial_text=denial_text,
            clinical_record=clinical_record
        );
        policy = Policy(
            policy_id="POL-BSH-44892-01",
            plan_name="BlueShield PPO Gold 2026",
            full_text=policy_text
        );
        root ++> claim;
        root ++> policy;

        # ---- 3. Agent: plan and execute the appeal --------------------
        letter = plan_and_generate_appeal(
            denial_text=denial_text,
            policy_text=policy_text,
            clinical_record=clinical_record,
            patient_name="Jordan A. Reyes",
            member_id="BSH-44892-01",
            claim_number="CLM-2026-0418-9921",
            date_of_service="2026-04-18",
            cpt_code="95810",
            billed_amount=3847.00,
            plan_name="BlueShield PPO Gold 2026"
        );

        # ---- 4. Persist the Appeal node -------------------------------
        appeal = Appeal(
            appeal_id=f"APL-{uuid.uuid4().hex[:8]}",
            claim_id=claim.claim_id,
            policy_id=policy.policy_id,
            denial_reason=DenialReason.NOT_MEDICALLY_NECESSARY,
            strength=AppealStrength.STRONG,
            contradictions_json="[]",
            letter_subject=letter.subject,
            letter_body=f"{letter.salutation}\n\n{letter.body}\n\n{letter.closing}",
            citations_json=json.dumps(letter.citations),
            created_at=datetime.datetime.utcnow().isoformat()
        );
        root ++> appeal;

        # ---- 5. Render the appeal -------------------------------------
        _banner("GENERATED APPEAL LETTER");
        print(f"Subject: {letter.subject}");
        print("");
        print(letter.salutation);
        print("");
        print(letter.body);
        print("");
        print(letter.closing);

        _banner("CITATIONS");
        for c in letter.citations {
            print(f"  • {c}");
        }

        _banner("PERSISTED ON GRAPH");
        print(f"  Appeal ID:  {appeal.appeal_id}");
        print(f"  Claim ID:   {appeal.claim_id}");
        print(f"  Policy ID:  {appeal.policy_id}");
        print(f"  Created at: {appeal.created_at}");
        print("");
        print("(These nodes persist on root and survive subsequent `jac run`s.)");
    }
}
