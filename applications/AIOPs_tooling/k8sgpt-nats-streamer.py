import asyncio
import json
from nats.aio.client import Client as NATS
from kubernetes import client, config, watch


async def publish_to_nats(nc, payload):
    """Publish and flush to ensure delivery."""
    await nc.publish("aiops.alerts", json.dumps(payload).encode())
    await nc.flush()  # Ensure message is sent
    print(f"Published alert to NATS: {payload['name']}", flush=True)


async def main():
    nc = NATS()
    print("[startup] Connecting to NATS...", flush=True)
    await nc.connect("nats://nats-service.default.svc.cluster.local:4222")
    print(f"[startup] ✅ Connected to NATS: {nc.is_connected}", flush=True)

    config.load_incluster_config()
    api = client.CustomObjectsApi()

    print("[startup] Watching for K8sGPT Result CRDs...", flush=True)
    w = watch.Watch()

    # Run blocking watch in executor to not block event loop
    loop = asyncio.get_event_loop()

    def watch_results():
        return list(w.stream(api.list_cluster_custom_object,
                             group="core.k8sgpt.ai",
                             version="v1alpha1",
                             plural="results",
                             timeout_seconds=10))

    while True:
        try:
            # Run blocking watch in thread pool
            events = await loop.run_in_executor(None, watch_results)

            for event in events:
                if event['type'] in ('ADDED', 'MODIFIED'):
                    result_obj = event['object']
                    payload = {
                        "name": result_obj['metadata']['name'],
                        "namespace": result_obj['metadata'].get('namespace', 'unknown'),
                        "error": result_obj['spec'].get('error', []),
                        "details": result_obj['spec'].get('details', '')
                    }
                    await publish_to_nats(nc, payload)
        except Exception as e:
            print(f"[error] Watch error: {e}", flush=True)

        await asyncio.sleep(1)


if __name__ == '__main__':
    asyncio.run(main())