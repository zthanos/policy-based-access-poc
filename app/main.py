import base64
import json
import logging
import time
from typing import Any

from fastapi import FastAPI, Request
from opentelemetry import propagate, trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.trace import SpanKind, Status, StatusCode

from telemetry import configure_tracing


logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("rest-api")

configure_tracing()
tracer = trace.get_tracer("authz-poc.rest-api")
app = FastAPI(title="Authorization PoC REST API")
FastAPIInstrumentor.instrument_app(app)


def _decode_gateway_payload(request: Request) -> dict[str, Any]:
    payload = request.headers.get("x-jwt-payload")
    if not payload:
        return {}

    try:
        padding = "=" * (-len(payload) % 4)
        decoded = base64.urlsafe_b64decode(f"{payload}{padding}")
        return json.loads(decoded)
    except (ValueError, json.JSONDecodeError):
        return {}


def _roles(identity: dict[str, Any]) -> list[str]:
    roles = identity.get("roles", [])
    return roles if isinstance(roles, list) else []


def _route_name(request: Request) -> str:
    route = request.scope.get("route")
    return getattr(route, "path", request.url.path)


def _trace_id() -> str:
    span_context = trace.get_current_span().get_span_context()
    if not span_context.is_valid:
        return ""
    return f"{span_context.trace_id:032x}"


def _authorization_reason(path: str, identity: dict[str, Any], requested_customer_id: str | None = None) -> str:
    roles = _roles(identity)
    if path == "/health":
        return "public health endpoint"
    if "admin" in roles:
        return "admin role is allowed"
    if requested_customer_id and requested_customer_id == identity.get("customer_id"):
        return "user customer_id matches requested customer"
    return "request already allowed by Envoy external authorization"


def trace_opa_decision(request: Request, identity: dict[str, Any], requested_customer_id: str | None = None) -> None:
    roles = _roles(identity)
    reason = _authorization_reason(request.url.path, identity, requested_customer_id)
    with tracer.start_as_current_span("OPA Authorization Decision") as span:
        span.set_attribute("requested_path", request.url.path)
        span.set_attribute("requested_customer_id", requested_customer_id or "")
        span.set_attribute("authenticated_customer_id", identity.get("customer_id", ""))
        span.set_attribute("roles", ",".join(roles))
        span.set_attribute("decision", "allow")
        span.set_attribute("reason", reason)
        span.set_attribute("opa.decision", "allow")
        span.set_attribute("opa.policy", "envoy.authz.allow")
        span.set_attribute("authorization.result", "allow")


@app.middleware("http")
async def request_logging(request: Request, call_next):
    started = time.monotonic()
    context = propagate.extract(dict(request.headers))
    with tracer.start_as_current_span(
        f"{request.method} {request.url.path}",
        context=context,
        kind=SpanKind.SERVER,
    ) as span:
        with tracer.start_as_current_span("JWT Validation Context") as jwt_span:
            identity = _decode_gateway_payload(request)
            username = identity.get("preferred_username", "anonymous")
            roles = _roles(identity)
            jwt_span.set_attribute("enduser.id", username)
            jwt_span.set_attribute("user.role", ",".join(roles))
            jwt_span.set_attribute("customer.id", identity.get("customer_id", ""))
            jwt_span.set_attribute("user.department", identity.get("department", ""))
            jwt_span.set_attribute("user.region", identity.get("region", ""))
            jwt_span.set_attribute("user.customer_segment", identity.get("customer_segment", ""))

        request.state.identity = identity
        span.set_attribute("http.method", request.method)
        span.set_attribute("http.target", request.url.path)
        span.set_attribute("enduser.id", username)
        span.set_attribute("user.role", ",".join(_roles(identity)))
        span.set_attribute("customer.id", identity.get("customer_id", ""))
        span.set_attribute("request.risk_level", request.headers.get("x-risk-level", "normal"))
        span.set_attribute("request.purpose", request.headers.get("x-purpose", ""))
        span.set_attribute("request.channel", request.headers.get("x-channel", "web"))
        span.set_attribute("request.time_window", request.headers.get("x-time-window", "business_hours"))
        span.set_attribute("request.device_trust", request.headers.get("x-device-trust", "trusted"))
        span.set_attribute("authorization.model", request.headers.get("x-authorization-model", ""))

        logger.info("incoming_request path=%s user=%s", request.url.path, username)
        response = await call_next(request)
        elapsed_ms = round((time.monotonic() - started) * 1000, 2)

        span.set_attribute("http.route", _route_name(request))
        span.set_attribute("http.status_code", response.status_code)
        if response.status_code >= 400:
            span.set_status(Status(StatusCode.ERROR))
        response.headers["x-trace-id"] = _trace_id()

        logger.info(
            "completed_request path=%s user=%s status=%s elapsed_ms=%s trace_id=%s",
            request.url.path,
            username,
            response.status_code,
            elapsed_ms,
            response.headers["x-trace-id"],
        )
        return response


@app.get("/health")
def health(request: Request):
    with tracer.start_as_current_span("Business Handler Execution") as span:
        span.set_attribute("http.route", "/health")
        return {"status": "ok"}


@app.get("/customers/{customer_id}/accounts")
def customer_accounts(customer_id: str, request: Request):
    identity = getattr(request.state, "identity", {})
    trace_opa_decision(request, identity, customer_id)
    with tracer.start_as_current_span("Business Handler Execution") as span:
        span.set_attribute("http.route", "/customers/{customer_id}/accounts")
        span.set_attribute("customer.id", customer_id)
        return {
            "customer_id": customer_id,
            "accounts": [
                {"id": f"{customer_id}-CHK", "type": "checking", "balance": 1250.0},
                {"id": f"{customer_id}-SAV", "type": "savings", "balance": 8750.0},
            ],
        }


@app.get("/admin/customers")
def admin_customers(request: Request):
    identity = getattr(request.state, "identity", {})
    trace_opa_decision(request, identity)
    with tracer.start_as_current_span("Business Handler Execution") as span:
        span.set_attribute("http.route", "/admin/customers")
        return {
            "customers": [
                {"customer_id": "CUST-001", "name": "Example Corporate GR"},
                {"customer_id": "CUST-002", "name": "Example Retail GR"},
                {"customer_id": "CUST-003", "name": "Example Corporate DE"},
            ]
        }
