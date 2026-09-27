"""Local portfolio workload: publish real custom metrics for simulated requests."""
import argparse
import json
import os
import random
import time
from datetime import datetime, timezone

import boto3


def publish_request(client, latency_ms, failed):
    """One API call, two bounded-cardinality, standard-resolution metrics."""
    timestamp = datetime.now(timezone.utc)
    dimensions = [{"Name": "App", "Value": "demo"}]
    client.put_metric_data(
        Namespace="PortfolioLab/Demo",
        MetricData=[
            {"MetricName": "RequestLatency", "Dimensions": dimensions,
             "Timestamp": timestamp, "Value": latency_ms, "Unit": "Milliseconds"},
            {"MetricName": "ErrorCount", "Dimensions": dimensions,
             "Timestamp": timestamp, "Value": int(failed), "Unit": "Count"},
        ],
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region", default=os.getenv("AWS_DEFAULT_REGION", "us-east-1"))
    parser.add_argument("--requests", type=int, default=10)
    parser.add_argument("--error-rate", type=float, default=0.0)
    parser.add_argument("--interval", type=float, default=1.0)
    args = parser.parse_args()
    if not 1 <= args.requests <= 1000:
        parser.error("--requests must be between 1 and 1000")
    if not 0 <= args.error_rate <= 1:
        parser.error("--error-rate must be between 0 and 1")
    if not 0 <= args.interval <= 60:
        parser.error("--interval must be between 0 and 60 seconds")

    # Uses the standard AWS credential chain. Never embed access keys.
    client = boto3.client("cloudwatch", region_name=args.region)
    for index in range(args.requests):
        start = time.perf_counter()
        time.sleep(random.uniform(0.01, 0.05))
        failed = random.random() < args.error_rate
        latency_ms = (time.perf_counter() - start) * 1000
        publish_request(client, latency_ms, failed)
        # Local stdout only. CloudWatch Logs ingestion is deliberately separate.
        print(json.dumps({"request": index + 1, "level": "ERROR" if failed else "INFO",
                          "latency_ms": round(latency_ms, 2), "simulated": True}), flush=True)
        if index + 1 < args.requests:
            time.sleep(args.interval)


if __name__ == "__main__":
    main()
