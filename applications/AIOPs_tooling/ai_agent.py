import gzip
import asyncio
import json
import os
from collections import deque
from nats.aio.client import Client as NATS
from github import Github, Auth
from langchain_openai import ChatOpenAI
from langchain_core.prompts import PromptTemplate

# Initialize State (Debouncing cache to prevent PR storms)
processed_alerts = set()


otel_buffer = deque(maxlen=5)
# Initialize LLM and GitHub
llm = ChatOpenAI(temperature=0, model_name="gpt-4o")
auth = Auth.Token(os.getenv("GITHUB_TOKEN"))
github_client = Github(auth=auth)
repo = github_client.get_repo("dima100/AI_OPS_Project_demo")

prompt_template = PromptTemplate(
    input_variables=["error_details", "resource_name", "telemetry_context"],
    template="""
You are an expert Kubernetes AIOps agent. 
A workload named {resource_name} is failing.

K8sGPT Diagnosis:
{error_details}

OpenTelemetry Context (Recent App Traces/Metrics):
{telemetry_context}

IMPORTANT - Our GitOps repo structure:
- Kubernetes deployment manifests are located in: terraform/modules/k8s_workloads/templates/
- Available files include:
  - demo-app-deployment.yaml
  - mysql-exporter-deployment.yaml
  - otel-collector-deployment.yaml
  - jaeger-deployment.yaml

Determine the GitOps remediation based on the error:
- If it is an OOMKill or memory issue, increase the memory limit in the relevant deployment.
- If it is an ImagePullBackOff, fix the image tag in the relevant deployment.
- If it is a database connection issue, fix the secret mapping.

Return ONLY valid JSON (no markdown, no explanation) in this format:
{{"file_path": "terraform/modules/k8s_workloads/templates/<filename>.yaml", "search_string": "exact string to find", "replace_string": "replacement string"}}

If the error is not related to any files in our repo or cannot be fixed via GitOps, return:
{{"skip": true, "reason": "brief explanation"}}
"""
)


async def otel_handler(msg):
    try:
        raw_data = msg.data
        print(f"[otel] 📨 Received {len(raw_data)} bytes from {msg.subject}", flush=True)
        print(f"[otel] 📨 First 20 bytes (hex): {raw_data[:20].hex()}", flush=True)
        # print(f"[otel] 📨 First 100 bytes (repr): {repr(raw_data[:100])}", flush=True)
        # Check if data is gzip-compressed (magic bytes: 0x1f 0x8b)
        if raw_data[:2] == b'\x1f\x8b':
            raw_data = gzip.decompress(raw_data)

        data = json.loads(raw_data.decode())
        otel_buffer.append(json.dumps(data)[:1000])
        # Pretty print (truncate to first 1000 chars)
        pretty = json.dumps(data, indent=2)
        # print(f"[otel] 📄 Received from {msg.subject}:\n{pretty}", flush=True)
        print(f"[otel] 📥 Buffered telemetry from {msg.subject}", flush=True)
    except Exception as e:
        print(f"[otel] ❌ Failed to parse OTel data: {e}", flush=True)
        print(f"[otel] ❌ Raw data type: {type(msg.data)}, length: {len(msg.data)}", flush=True)


async def message_handler(msg):
    try:
        data = json.loads(msg.data.decode())
        alert_id = data['name']
        print(f"[alert] processing {alert_id}", flush=True)

        # 1. State Check: Prevent infinite loops
        if alert_id in processed_alerts:
            print(f"[alert] Already processing {alert_id}, skipping.", flush=True)
            return
        processed_alerts.add(alert_id)

        print(f"[alert] Investigating anomaly: {data['error']}", flush=True)
        telemetry_context = "\n---\n".join(otel_buffer) if otel_buffer else "No recent OTel telemetry available."

        # 2. Query LLM for remediation strategy
        prompt = prompt_template.format(
            resource_name=alert_id,
            error_details=json.dumps(data['error']),
            telemetry_context=telemetry_context
        )

        print(f"[llm] Sending prompt to LLM...", flush=True)
        response = llm.invoke(prompt)
        llm_response = response.content
        print(f"[llm] Raw LLM response: {llm_response}", flush=True)

        if not llm_response or not llm_response.strip():
            print(f"[llm] ❌ Empty response from LLM, skipping.", flush=True)
            return

        # Try to extract JSON from response (LLM might wrap it in markdown)
        json_match = llm_response.strip()
        if json_match.startswith("```"):
            # Remove markdown code blocks
            json_match = json_match.split("```")[1]
            if json_match.startswith("json"):
                json_match = json_match[4:]

        remediation = json.loads(json_match.strip())
        print(f"[llm] Parsed remediation: {remediation}", flush=True)
        if remediation.get("skip"):
            print(f"[llm] ⏭️ LLM skipped remediation: {remediation.get('reason')}", flush=True)
            return

        try:
            file_content = repo.get_contents(remediation["file_path"])
        except Exception as e:
            print(f"[error] ❌ File not found in repo: {remediation['file_path']}", flush=True)
            print(f"[error] Skipping PR creation for {alert_id}", flush=True)
            return
        # 3. GitOps PR Generation
        file_content = repo.get_contents(remediation["file_path"])
        decoded_content = file_content.decoded_content.decode("utf-8")

        new_content = decoded_content.replace(
            remediation["search_string"],
            remediation["replace_string"]
        )

        # Create a new branch and PR
        branch_name = f"aiops-remediation-{alert_id}"
        repo.create_git_ref(ref=f"refs/heads/{branch_name}", sha=repo.get_branch("main").commit.sha)

        repo.update_file(
            file_content.path,
            f"AIOps: Automated remediation for {alert_id}",
            new_content,
            file_content.sha,
            branch=branch_name
        )

        pr = repo.create_pull(
            title=f"🚨 AIOps Auto-Fix: {alert_id}",
            body=f"Automated PR generated by K8sGPT Agent.\n\n**Diagnosis:**\n{data['details']}",
            head=branch_name,
            base="main"
        )
        print(f"[pr] ✅ Created GitOps Pull Request: {pr.html_url}", flush=True)

    except json.JSONDecodeError as e:
        print(f"[error] ❌ Failed to parse LLM response as JSON: {e}", flush=True)
        print(f"[error] Response was: {llm_response if 'llm_response' in dir() else 'N/A'}", flush=True)
    except Exception as e:
        print(f"[error] ❌ Error in message_handler: {e}", flush=True)

async def main():
    nc = NATS()
    await nc.connect("nats://nats-service.default.svc.cluster.local:4222")

    # Subscribe to the alert stream
    sub = await nc.subscribe("aiops.alerts", cb=message_handler)
    print(f"[startup] ✅ Subscribed to aiops.alerts (sub id: {sub._id})", flush=True)
    await nc.subscribe("aiops.alerts.otel.traces", cb=otel_handler)
    await nc.subscribe("aiops.alerts.otel.metrics", cb=otel_handler)

    print("AI Agent listening for cluster anomalies and OpenTelemetry events...")
    # Keep alive
    while True:
        await asyncio.sleep(1)


if __name__ == '__main__':
    asyncio.run(main())