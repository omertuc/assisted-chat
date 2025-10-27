"""Agent goal evaluation."""

import argparse
import logging
import sys
import os

from lsc_agent_eval import AgentGoalEval
from junit_reporter import generate_junit_xml

# Configure logging to show all messages from agent_eval library
logging.basicConfig(
    level=logging.WARNING,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)

# Enable specific loggers we want to see
logging.getLogger("lsc_agent_eval").setLevel(logging.INFO)


# Create proper Namespace object for AgentGoalEval
def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Agent goal evaluation")

    parser.add_argument(
        "--eval_data_yaml",
        default="eval_data.yaml",
        help="Path to evaluation data YAML file (default: eval_data.yaml)",
    )

    parser.add_argument(
        "--agent_endpoint",
        default="http://localhost:8090",
        help="Agent endpoint URL (default: http://localhost:8090)",
    )

    parser.add_argument(
        "--endpoint_type",
        choices=["streaming", "query"],
        default="streaming",
        help="Endpoint type to use for agent queries (default: streaming)",
    )

    parser.add_argument(
        "--agent_provider", default="gemini", help="Agent provider (default: gemini)"
    )

    parser.add_argument(
        "--agent_model",
        default="gemini-2.0-flash",
        help="Agent model (default: gemini-2.0-flash)",
    )

    parser.add_argument(
        "--judge_provider",
        default="gemini",
        help="Judge provider for LLM evaluation (default: gemini)",
    )

    parser.add_argument(
        "--judge_model",
        default="gemini-2.5-flash",
        help="Judge model for LLM evaluation (default: gemini-2.0-flash)",
    )

    parser.add_argument(
        "--agent_auth_token_file",
        default="ocm_token.txt",
        help="Path to agent auth token file (default: ocm_token.txt)",
    )

    parser.add_argument(
        "--result_dir",
        default="eval_output",
        help="Directory for evaluation results (default: eval_output)",
    )

    return parser.parse_args()


# Parse command line arguments
args = parse_args()
if os.getenv('UNIQUE_ID') is None:
    print("The environmental varialbe 'UNIQUE_ID' has to be set so the cluster creation and removal can happen properly.")
    sys.exit(1)

evaluator = AgentGoalEval(args)
# Run Evaluation
evaluator.run_evaluation()
# Get result summary
result_summary = evaluator.get_result_summary()

# Generate JUnit XML for spyglass
artifacts_dir = os.getenv('ARTIFACTS_DIR', 'eval_output')
generate_junit_xml(evaluator, artifacts_dir)

failed_evals_count = result_summary["FAIL"] + result_summary["ERROR"]
if failed_evals_count:
    print(f"❌ {failed_evals_count} evaluation(s) failed!")
    sys.exit(1)

print("🎉 All evaluations passed!")
sys.exit(0)
