"""Offline contract tests. No AWS requests are sent."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

import boto3
from botocore.stub import ANY, Stubber

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("app", ROOT / "sample-app/app.py")
app = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(app)


class PublisherTests(unittest.TestCase):
    def test_metric_payload(self):
        client = boto3.client("cloudwatch", region_name="us-east-1",
                              aws_access_key_id="offline", aws_secret_access_key="offline")
        with Stubber(client) as stub:
            for failed in (False, True):
                stub.add_response("put_metric_data", {}, {
                    "Namespace": "PortfolioLab/Demo",
                    "MetricData": [
                        {"MetricName": "RequestLatency", "Dimensions": [{"Name": "App", "Value": "demo"}],
                         "Timestamp": ANY, "Value": 12.5, "Unit": "Milliseconds"},
                        {"MetricName": "ErrorCount", "Dimensions": [{"Name": "App", "Value": "demo"}],
                         "Timestamp": ANY, "Value": int(failed), "Unit": "Count"},
                    ],
                })
                app.publish_request(client, 12.5, failed)
            stub.assert_no_pending_responses()

    def test_traffic_script(self):
        # Capture the actual script arguments without sending AWS requests,
        # then exercise those arguments with an in-process mocked SDK.
        result = subprocess.run(
            ["bash", str(ROOT / "sample-app/simulate-traffic.sh")],
            env={"PATH": "/usr/bin:/bin", "PYTHON": "/bin/echo"},
            capture_output=True, text=True, check=True,
        )
        self.assertIn("app.py", result.stdout)
        argv = result.stdout.strip().split()
        self.assertEqual(argv[1:], ["--requests", "40", "--error-rate", "1", "--interval", "0.1"])
        with patch.object(sys, "argv", argv), \
                patch.object(app.boto3, "client") as factory, \
                patch.object(app.time, "sleep"), patch("builtins.print"):
            app.main()
        calls = factory.return_value.put_metric_data.call_args_list
        self.assertEqual(len(calls), 40)
        self.assertTrue(all(call.kwargs["MetricData"][1]["Value"] == 1 for call in calls))

    def test_invalid_rate(self):
        with patch.object(sys, "argv", ["app.py", "--error-rate", "2"]), \
                patch.object(app.boto3, "client") as factory:
            with self.assertRaises(SystemExit):
                app.main()
            factory.assert_not_called()


if __name__ == "__main__":
    unittest.main()
