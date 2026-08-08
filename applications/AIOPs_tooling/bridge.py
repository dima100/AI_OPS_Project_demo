import asyncio
from fastapi import FastAPI, Request
from nats.aio.client import Client as NATS

app = FastAPI()
nc = NATS()

@app.on_event("startup")
async def startup_event():
    # Connect to the exact same NATS broker as the streamer
    await nc.connect("nats://nats-service.default.svc.cluster.local:4222")
    print("✅ OTel Bridge connected to NATS")

@app.on_event("shutdown")
async def shutdown_event():
    await nc.close()

@app.post("/v1/traces")
async def receive_traces(request: Request):
    payload = await request.body()
    await nc.publish("aiops.alerts.otel.traces", payload)
    return {"status": "ok"}

@app.post("/v1/metrics")
async def receive_metrics(request: Request):
    payload = await request.body()
    await nc.publish("aiops.alerts.otel.metrics", payload)
    return {"status": "ok"}