#!/usr/bin/env python3
"""Append a Prometheus federation scrape job to an existing prometheus.yml.
Usage:
    inject-federation.py <host:port> [<host:port> ...]
"""
import json
import sys

import yaml

JOB_NAME = "federate-remotes"

def main() -> int:
    targets = sys.argv[1:]
    if not targets:
        print("usage: inject-federation.py <host:port> [<host:port> ...]", file=sys.stderr)
        return 1

    config = yaml.safe_load(sys.stdin.read()) or {}

    job = {
        "job_name": JOB_NAME,
        "honor_labels": True,
        "metrics_path": "/federate",
        "params": {"match[]": ['{__name__=~"istio.*"}']},
        "static_configs": [{"targets": targets}],
    }

    scrape_configs = config.get("scrape_configs") or []
    scrape_configs = [j for j in scrape_configs if j.get("job_name") != JOB_NAME]
    scrape_configs.append(job)
    config["scrape_configs"] = scrape_configs

    rendered = yaml.safe_dump(config, default_flow_style=False, sort_keys=False)
    print(json.dumps({"data": {"prometheus.yml": rendered}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())