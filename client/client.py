import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass

from opentelemetry import propagate, trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.trace import SpanKind, Status, StatusCode


KEYCLOAK_URL = os.getenv("KEYCLOAK_URL", "http://localhost:8031")
API_URL = os.getenv("API_URL", "http://localhost:10000")
OTEL_EXPORTER_OTLP_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318/v1/traces")
REALM = os.getenv("KEYCLOAK_REALM", "poc")
CLIENT_ID = os.getenv("KEYCLOAK_CLIENT_ID", "poc-client")
PASSWORD = os.getenv("KEYCLOAK_PASSWORD", "password")
KEYCLOAK_HOST_HEADER = os.getenv("KEYCLOAK_HOST_HEADER", "localhost:8031")


@dataclass
class Result:
    label: str
    status: int
    expected: int
    trace_id: str


def configure_tracing() -> None:
    resource = Resource.create(
        {
            "service.name": "external-client",
            "service.namespace": "authz-poc",
            "deployment.environment": "local",
        }
    )
    provider = TracerProvider(resource=resource)
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=OTEL_EXPORTER_OTLP_ENDPOINT)))
    trace.set_tracer_provider(provider)


tracer = trace.get_tracer("authz-poc.external-client")


def request_token(username: str) -> str:
    data = urllib.parse.urlencode(
        {
            "grant_type": "password",
            "client_id": CLIENT_ID,
            "username": username,
            "password": PASSWORD,
        }
    ).encode()
    url = f"{KEYCLOAK_URL}/realms/{REALM}/protocol/openid-connect/token"
    request = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Host": KEYCLOAK_HOST_HEADER,
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        body = json.loads(response.read().decode())
        return body["access_token"]


def _current_trace_id() -> str:
    context = trace.get_current_span().get_span_context()
    if not context.is_valid:
        return ""
    return f"{context.trace_id:032x}"


def call_api(
    method: str,
    path: str,
    token: str | None = None,
    extra_headers: dict[str, str] | None = None,
) -> tuple[int, str, str]:
    headers = extra_headers.copy() if extra_headers else {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    propagate.inject(headers)

    request = urllib.request.Request(
        f"{API_URL}{path}",
        headers=headers,
        method=method,
    )

    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            trace_id = response.headers.get("x-trace-id") or _current_trace_id()
            return response.status, response.read().decode(), trace_id
    except urllib.error.HTTPError as exc:
        trace_id = exc.headers.get("x-trace-id") or _current_trace_id()
        return exc.code, exc.read().decode(), trace_id


def run_case(
    label: str,
    method: str,
    path: str,
    expected: int,
    token: str | None = None,
    extra_headers: dict[str, str] | None = None,
    authorization_model: str = "n/a",
) -> Result:
    with tracer.start_as_current_span(label, kind=SpanKind.CLIENT) as span:
        headers = extra_headers.copy() if extra_headers else {}
        if authorization_model != "n/a":
            headers["x-authorization-model"] = authorization_model

        span.set_attribute("http.method", method)
        span.set_attribute("http.url", f"{API_URL}{path}")
        span.set_attribute("http.target", path)
        span.set_attribute("authorization.model", authorization_model)
        span.set_attribute("authorization.scenario", label)
        status, _, trace_id = call_api(method, path, token, headers)
        span.set_attribute("http.status_code", status)
        span.set_attribute("authorization.result", "allow" if status == 200 else "deny")
        if status >= 400:
            span.set_status(Status(StatusCode.ERROR))
        trace_id = trace_id or _current_trace_id()
        print(f"{label:<44} -> {status} trace_id={trace_id}")
        return Result(label, status, expected, trace_id)


def main() -> int:
    configure_tracing()
    print(f"Keycloak: {KEYCLOAK_URL}")
    print(f"APIM:     {API_URL}")
    print(f"OTLP:     {OTEL_EXPORTER_OTLP_ENDPOINT}")
    print()

    user_token = request_token("user1")
    admin_token = request_token("admin")
    auditor_token = request_token("auditor1")

    results = [
        run_case("GET /health", "GET", "/health", 200, authorization_model="Public"),
        run_case(
            "GET /customers/CUST-001/accounts",
            "GET",
            "/customers/CUST-001/accounts",
            200,
            user_token,
            authorization_model="Customer Scope",
        ),
        run_case(
            "GET /customers/CUST-002/accounts",
            "GET",
            "/customers/CUST-002/accounts",
            403,
            user_token,
            authorization_model="Customer Scope",
        ),
        run_case(
            "ABAC RM GR -> CUST-001 GR",
            "GET",
            "/customers/CUST-001/accounts",
            200,
            user_token,
            authorization_model="ABAC",
        ),
        run_case(
            "ABAC RM GR -> CUST-003 DE",
            "GET",
            "/customers/CUST-003/accounts",
            403,
            user_token,
            authorization_model="ABAC",
        ),
        run_case(
            "ABAC high risk request",
            "GET",
            "/customers/CUST-001/accounts",
            403,
            user_token,
            {"x-risk-level": "high"},
            authorization_model="ABAC",
        ),
        run_case(
            "ReBAC user1 -> CUST-001",
            "GET",
            "/customers/CUST-001/accounts",
            200,
            user_token,
            authorization_model="ReBAC",
        ),
        run_case(
            "ReBAC user1 -> CUST-002",
            "GET",
            "/customers/CUST-002/accounts",
            403,
            user_token,
            authorization_model="ReBAC",
        ),
        run_case(
            "ReBAC auditor1 audit CUST-002",
            "GET",
            "/customers/CUST-002/accounts",
            200,
            auditor_token,
            {"x-purpose": "audit"},
            authorization_model="ReBAC",
        ),
        run_case(
            "ReBAC auditor1 sales CUST-002",
            "GET",
            "/customers/CUST-002/accounts",
            403,
            auditor_token,
            {"x-purpose": "sales"},
            authorization_model="ReBAC",
        ),
        run_case(
            "GET /admin/customers as user1",
            "GET",
            "/admin/customers",
            403,
            user_token,
            authorization_model="RBAC",
        ),
        run_case(
            "GET /admin/customers as admin",
            "GET",
            "/admin/customers",
            200,
            admin_token,
            authorization_model="RBAC",
        ),
        run_case(
            "GET /customers/CUST-001/accounts no token",
            "GET",
            "/customers/CUST-001/accounts",
            401,
            authorization_model="Authentication",
        ),
    ]

    failures = [result for result in results if result.status != result.expected]
    if failures:
        print()
        print("Failures:")
        for failure in failures:
            print(f"- {failure.label}: expected {failure.expected}, got {failure.status}")
        return 1

    print()
    print("All scenarios passed.")
    trace.get_tracer_provider().force_flush(timeout_millis=5000)
    trace.get_tracer_provider().shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
