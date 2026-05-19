# walkers.jac — REST surface.
#
# `jac serve walkers.jac` exposes each walker as a POST endpoint at
# /walker/<name>. The `has` fields become the JSON request body.

import json;
import uuid;
import datetime;

import from models { Claim, Policy, Appeal, DenialReason, AppealStrength, Contradiction }
import from orchestrator { plan_and_generate_appeal }


# ---- Walker: full agentic pipeline -------------------------------------
#
# POST /walker/submit_claim
# Body: {
#   "patient_name": "...",
#   "member_id": "...",
#   "claim_number": "...",
#   "date_of_service": "YYYY-MM-DD",
#   "cpt_code": "...",
#   "billed_amount": 0.0,
#   "plan_name": "...",
#   "denial_text": "...",
#   "policy_text": "...",
#   "clinical_record": ""        # optional
# }

walker:pub submit_claim {
    has patient_name: str;
    has member_id: str;
    has claim_number: str;
    has date_of_service: str;
    has cpt_code: str;
    has billed_amount: float;
    has plan_name: str;
    has denial_text: str;
    has policy_text: str;
    has clinical_record: str = "";

    can run with Root entry {
        # 1. Persist the inputs on the graph so the appeal can reference
        #    them later. Connecting to root makes Jac auto-persist.
        claim = Claim(
            claim_id=self.claim_number,
            patient_name=self.patient_name,
            member_id=self.member_id,
            cpt_code=self.cpt_code,
            date_of_service=self.date_of_service,
            billed_amount=self.billed_amount,
            denial_text=self.denial_text,
            clinical_record=self.clinical_record
        );
        policy = Policy(
            policy_id=f"POL-{self.member_id}",
            plan_name=self.plan_name,
            full_text=self.policy_text
        );
        here ++> claim;
        here ++> policy;

        # 2. Let the agent plan and execute the appeal end-to-end.
        #    THIS is the agentic call — the LLM picks tool order.
        letter = plan_and_generate_appeal(
            denial_text=self.denial_text,
            policy_text=self.policy_text,
            clinical_record=self.clinical_record,
            patient_name=self.patient_name,
            member_id=self.member_id,
            claim_number=self.claim_number,
            date_of_service=self.date_of_service,
            cpt_code=self.cpt_code,
            billed_amount=self.billed_amount,
            plan_name=self.plan_name
        );

        # 3. Persist the resulting Appeal.
        appeal = Appeal(
            appeal_id=f"APL-{uuid.uuid4().hex[:8]}",
            claim_id=claim.claim_id,
            policy_id=policy.policy_id,
            denial_reason=DenialReason.OTHER,           # tracked at letter level
            strength=AppealStrength.MODERATE,
            contradictions_json="[]",
            letter_subject=letter.subject,
            letter_body=f"{letter.salutation}\n\n{letter.body}\n\n{letter.closing}",
            citations_json=json.dumps(letter.citations),
            created_at=datetime.datetime.utcnow().isoformat()
        );
        here ++> appeal;

        report {
            "appeal_id": appeal.appeal_id,
            "claim_id": claim.claim_id,
            "subject": letter.subject,
            "letter": appeal.letter_body,
            "citations": letter.citations
        };
    }
}


# ---- Walker: list all appeals on the graph -----------------------------
#
# POST /walker/list_appeals
# Body: {}

walker:pub list_appeals {
    can run with Root entry {
        appeals = [-->[?:Appeal]];
        rows = [];
        for a in appeals {
            rows.append({
                "appeal_id": a.appeal_id,
                "claim_id": a.claim_id,
                "subject": a.letter_subject,
                "created_at": a.created_at
            });
        }
        report rows;
    }
}
