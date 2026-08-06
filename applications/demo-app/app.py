import os
import pymysql
from fastapi import FastAPI
from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.pymysql import PyMySQLInstrumentor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource

# 1. Configure OpenTelemetry
resource = Resource(attributes={"service.name": "mysql-demo-app"})
provider = TracerProvider(resource=resource)
processor = BatchSpanProcessor(OTLPSpanExporter(endpoint="http://otel-collector:4317", insecure=True))
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)

app = FastAPI()

# 2. Instrument FastAPI and PyMySQL
FastAPIInstrumentor.instrument_app(app)
PyMySQLInstrumentor().instrument()

def get_db_connection():
    return pymysql.connect(
        host=os.getenv("MYSQL_HOST", "mysql-service"),
        user=os.getenv("MYSQL_USER", "root"),
        password=os.getenv("MYSQL_PASSWORD", "secret"),
        database=os.getenv("MYSQL_DB", "demo_db")
    )

@app.get("/users")
def get_users():
    # This query will be automatically traced by OTel
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT id, name FROM users LIMIT 10;")
            result = cursor.fetchall()
            return {"users": result}
    finally:
        conn.close()