FROM python:3.11-slim
WORKDIR /app
COPY k8sgpt-nats-streamer.py .
COPY ai_agent.py .
COPY bridge.py .
RUN pip install kubernetes nats-py langchain langchain-core langchain-openai openai PyGithub fastapi uvicorn
# We don't set a CMD here. We will define it in the Kubernetes YAML.