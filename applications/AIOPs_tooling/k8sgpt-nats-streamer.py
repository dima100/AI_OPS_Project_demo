import asyncio
import json
from nats.aio.client import Client as NATS
from kubernetes import client, config, watch


async def main():
    # Connect to NATS broker in the cluster
    nc = NATS()
    await nc.connect("nats://nats-service.default.svc.cluster.local:4222")

    # Load in-cluster Kubernetes config
    config.load_incluster_config()
    api = client.CustomObjectsApi()

    print("Watching for K8sGPT Result CRDs...")
    w = watch.Watch()

    # Watch the core.k8sgpt.ai/v1alpha1 Result stream
    for event in w.stream(api.list_cluster_custom_object,
                          group="core.k8sgpt.ai",
                          version="v1alpha1",
                          plural="results"):

        if event['type'] == 'ADDED' or event['type'] == 'MODIFIED':
            result_obj = event['object']
            payload = {
                "name": result_obj['metadata']['name'],
                "namespace": result_obj['metadata']['namespace'],
                "error": result_obj['spec'].get('error', []),
                "details": result_obj['spec'].get('details', '')
            }

            # Publish the K8sGPT diagnosis to NATS
            await nc.publish("aiops.alerts", json.dumps(payload).encode())
            print(f"Published alert to NATS: {payload['name']}")


if __name__ == '__main__':
    asyncio.run(main())