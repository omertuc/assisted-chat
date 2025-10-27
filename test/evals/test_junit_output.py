#!/usr/bin/env python3
"""Test script to verify JUnit XML output format."""

import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest.mock import Mock

from junit_reporter import generate_junit_xml


def create_mock_evaluator():
    """Create a mock evaluator with test data."""
    evaluator = Mock()

    # Mock result summary
    evaluator.get_result_summary.return_value = {
        "TOTAL": 3,
        "PASS": 1,
        "FAIL": 1,
        "ERROR": 1
    }

    return evaluator


def test_basic_junit_generation():
    """Test basic JUnit XML generation when detailed results are not available."""
    evaluator = create_mock_evaluator()

    with tempfile.TemporaryDirectory() as temp_dir:
        generate_junit_xml(evaluator, temp_dir)

        # Check if XML file was created
        xml_files = list(Path(temp_dir).glob("junit*.xml"))
        assert len(xml_files) > 0, "No JUnit XML files were created"

        # Parse and validate XML structure
        xml_file = xml_files[0]
        tree = ET.parse(xml_file)
        root = tree.getroot()

        # Validate structure
        assert root.tag == "testsuites", f"Root element should be 'testsuites', got '{root.tag}'"

        testsuites = root.findall("testsuite")
        assert len(testsuites) == 1, f"Expected 1 testsuite, got {len(testsuites)}"

        testsuite = testsuites[0]
        assert testsuite.get("tests") == "3", f"Expected 3 tests, got {testsuite.get('tests')}"
        assert testsuite.get("failures") == "1", f"Expected 1 failure, got {testsuite.get('failures')}"
        assert testsuite.get("errors") == "1", f"Expected 1 error, got {testsuite.get('errors')}"

        # Check test case
        testcases = testsuite.findall("testcase")
        assert len(testcases) == 1, f"Expected 1 testcase, got {len(testcases)}"

        testcase = testcases[0]
        assert testcase.get("classname") == "AgentGoalEval", f"Expected classname 'AgentGoalEval', got {testcase.get('classname')}"
        assert testcase.get("name") == "evaluation_summary", f"Expected name 'evaluation_summary', got {testcase.get('name')}"

        # Check for failure element since we have failures
        failures = testcase.findall("failure")
        assert len(failures) == 1, f"Expected 1 failure element, got {len(failures)}"

        print(f"✅ Basic JUnit XML test passed! XML file: {xml_file}")
        return True


def validate_xml_against_junit_schema(xml_file):
    """Basic validation that XML follows JUnit format expectations."""
    tree = ET.parse(xml_file)
    root = tree.getroot()

    # Basic structure checks
    assert root.tag == "testsuites"

    for testsuite in root.findall("testsuite"):
        # Required attributes
        required_attrs = ["name", "tests", "failures", "errors"]
        for attr in required_attrs:
            assert testsuite.get(attr) is not None, f"Missing required attribute: {attr}"

        for testcase in testsuite.findall("testcase"):
            # Required attributes
            required_attrs = ["classname", "name"]
            for attr in required_attrs:
                assert testcase.get(attr) is not None, f"Missing required attribute: {attr}"

    print(f"✅ XML validation passed for: {xml_file}")


if __name__ == "__main__":
    try:
        print("Testing JUnit XML generation...")
        test_basic_junit_generation()
        print("🎉 All tests passed!")
    except Exception as e:
        print(f"❌ Test failed: {e}")
        exit(1)