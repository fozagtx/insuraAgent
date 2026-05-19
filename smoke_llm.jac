# Minimal byLLM smoke test.
# Run:  jac run smoke_llm.jac
#
# Requires ANTHROPIC_API_KEY or GEMINI_API_KEY in the environment.
# (Switch the model in jac.toml to use Gemini.)

import os;
import from byllm.llm { Model }

glob llm = Model(model_name="claude-sonnet-4-20250514");

def classify(text: str) -> str by llm();

with entry {
    have_anthropic = os.environ.get("ANTHROPIC_API_KEY", "") != "";
    have_gemini    = os.environ.get("GEMINI_API_KEY", "") != "";
    if not (have_anthropic or have_gemini) {
        print("ERROR: Set ANTHROPIC_API_KEY or GEMINI_API_KEY first.");
        print("  export ANTHROPIC_API_KEY=sk-ant-...");
        print("  # or");
        print("  export GEMINI_API_KEY=...    (then change model in jac.toml to gemini/gemini-2.0-flash)");
    } else {
        result = classify("Classify this in one word: a dog barking loudly at the mailman");
        print("LLM classification:", result);
    }
}
