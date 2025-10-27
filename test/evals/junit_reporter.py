"""JUnit XML reporter for agent evaluation results."""

import logging
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path


def generate_junit_xml(evaluator, output_dir):
    """Generate JUnit XML files from evaluation results for spyglass."""
    try:
        # Get the results manager to access detailed results
        results_manager = evaluator.evaluation_runner.results if hasattr(evaluator.evaluation_runner, 'results') else None

        # If we can't access detailed results, create a basic summary from result_summary
        if not results_manager:
            _generate_basic_junit_xml(evaluator, output_dir)
            return

        # Get detailed results
        results = results_manager.results if hasattr(results_manager, 'results') else []
        if not results:
            _generate_basic_junit_xml(evaluator, output_dir)
            return

        _generate_detailed_junit_xml(results, output_dir)

    except Exception as e:
        logging.warning(f"Failed to generate detailed JUnit XML: {e}")
        # Fallback to basic XML generation
        _generate_basic_junit_xml(evaluator, output_dir)


def _generate_basic_junit_xml(evaluator, output_dir):
    """Generate basic JUnit XML from summary results."""
    result_summary = evaluator.get_result_summary()

    # Create test suite
    testsuite = ET.Element("testsuite")
    testsuite.set("name", "Agent Goal Evaluations")
    testsuite.set("tests", str(result_summary.get("TOTAL", 0)))
    testsuite.set("failures", str(result_summary.get("FAIL", 0)))
    testsuite.set("errors", str(result_summary.get("ERROR", 0)))
    testsuite.set("time", "0")
    testsuite.set("timestamp", datetime.now().isoformat())

    # Create a single test case for summary
    testcase = ET.SubElement(testsuite, "testcase")
    testcase.set("classname", "AgentGoalEval")
    testcase.set("name", "evaluation_summary")
    testcase.set("time", "0")

    # Add failure if there were any failures or errors
    failed_count = result_summary.get("FAIL", 0) + result_summary.get("ERROR", 0)
    if failed_count > 0:
        failure = ET.SubElement(testcase, "failure")
        failure.set("message", f"{failed_count} evaluation(s) failed")
        failure.text = f"Failed: {result_summary.get('FAIL', 0)}, Errors: {result_summary.get('ERROR', 0)}"

    _write_junit_xml(testsuite, output_dir, "junit_basic_summary.xml")


def _generate_detailed_junit_xml(results, output_dir):
    """Generate detailed JUnit XML from individual evaluation results."""
    # Group results by conversation group
    conversations = {}
    for result in results:
        conv_group = result.conversation_group or "default"
        if conv_group not in conversations:
            conversations[conv_group] = []
        conversations[conv_group].append(result)

    # Create a test suite for each conversation group
    for conv_group, conv_results in conversations.items():
        testsuite = ET.Element("testsuite")
        testsuite.set("name", f"AgentGoalEval_{conv_group}")
        testsuite.set("tests", str(len(conv_results)))

        failures = sum(1 for r in conv_results if r.result == "FAIL")
        errors = sum(1 for r in conv_results if r.result == "ERROR")
        testsuite.set("failures", str(failures))
        testsuite.set("errors", str(errors))
        testsuite.set("time", "0")
        testsuite.set("timestamp", datetime.now().isoformat())

        # Create test case for each evaluation
        for result in conv_results:
            testcase = ET.SubElement(testsuite, "testcase")
            testcase.set("classname", f"AgentGoalEval.{conv_group}")
            testcase.set("name", f"{result.eval_id}_{result.eval_type}")
            testcase.set("time", "0")

            # Add system-out with query and response
            system_out = ET.SubElement(testcase, "system-out")
            system_out.text = f"Query: {result.query}\nResponse: {result.response}"

            # Add failure or error details
            if result.result == "FAIL":
                failure = ET.SubElement(testcase, "failure")
                failure.set("message", f"Evaluation failed: {result.eval_type}")
                failure_text = f"Eval Type: {result.eval_type}\nQuery: {result.query}\nResponse: {result.response}"
                if result.error:
                    failure_text += f"\nError: {result.error}"
                if result.tool_calls:
                    failure_text += f"\nTool Calls: {result.tool_calls}"
                if result.expected_intent:
                    failure_text += f"\nExpected Intent: {result.expected_intent}"
                failure.text = failure_text

            elif result.result == "ERROR":
                error = ET.SubElement(testcase, "error")
                error.set("message", f"Evaluation error: {result.eval_type}")
                error_text = f"Eval Type: {result.eval_type}\nQuery: {result.query}"
                if result.error:
                    error_text += f"\nError: {result.error}"
                error.text = error_text

        # Write XML file for this conversation group
        filename = f"junit_{conv_group.replace(' ', '_').replace('/', '_')}.xml"
        _write_junit_xml(testsuite, output_dir, filename)


def _write_junit_xml(testsuite_element, output_dir, filename):
    """Write JUnit XML to file."""
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    xml_file = output_path / filename

    # Create root element and add testsuite
    root = ET.Element("testsuites")
    root.append(testsuite_element)

    # Create tree and write to file
    tree = ET.ElementTree(root)
    ET.indent(tree, space="  ", level=0)
    tree.write(xml_file, encoding="utf-8", xml_declaration=True)

    print(f"📄 JUnit XML report saved: {xml_file}")