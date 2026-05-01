# Test Scenarios

| Scenario | User | Token | Expected |
| --- | --- | --- | --- |
| `GET /health` | anonymous | none | `200` |
| `GET /customers/CUST-001/accounts` | `user1` | valid | `200` |
| `GET /customers/CUST-002/accounts` | `user1` | valid | `403` |
| `ABAC RM GR -> CUST-001 GR` | `user1` | valid, `region=GR`, `x-risk-level=normal` | `200` |
| `ABAC RM GR -> CUST-003 DE` | `user1` | valid, `region=GR`, `x-risk-level=normal` | `403` |
| `ABAC high risk request` | `user1` | valid, `x-risk-level=high` | `403` |
| `ReBAC user1 -> CUST-001` | `user1` | valid, `relationship_manager_of CUST-001` | `200` |
| `ReBAC user1 -> CUST-002` | `user1` | valid, no relationship to `CUST-002` | `403` |
| `ReBAC auditor1 audit CUST-002` | `auditor1` | valid, `auditor_of CUST-002`, `x-purpose=audit` | `200` |
| `ReBAC auditor1 sales CUST-002` | `auditor1` | valid, `auditor_of CUST-002`, `x-purpose=sales` | `403` |
| `GET /admin/customers` | `user1` | valid | `403` |
| `GET /admin/customers` | `admin` | valid | `200` |
| `GET /customers/CUST-001/accounts` | anonymous | none | `401` |

## Authorization Models

The scenarios are ordered to show the progression from the existing RBAC/customer-scope PoC into a broader policy-based access control PoC:

- **RBAC**: role and customer-scope checks from the JWT.
- **ABAC**: user, customer, request, and environment attributes such as `region`, `segment`, `risk_level`, `channel`, `time_window`, and `device_trust`.
- **ReBAC**: relationship data such as `relationship_manager_of`, `auditor_of`, and `supervises`.

Each scenario prints `trace_id=...`. Use that id in Jaeger at `http://localhost:16686`.

All scenarios call the APIM simulator at `http://localhost:10000`. Envoy on `http://localhost:10080` is debug-only and is not used by the test client.

## Observability

Check component logs:

```powershell
kubectl logs -n gateway deploy/envoy
kubectl logs -n apim deploy/kong
kubectl logs -n authorization deploy/opa
kubectl logs -n app deploy/rest-api
kubectl logs -n observability deploy/otel-collector
kubectl logs -n observability deploy/jaeger
```

Envoy logs the request path and final status. OPA logs authorization decisions. FastAPI logs the incoming path, gateway-provided username, and final status.

In Jaeger, use the `external-client` service and filter by `authorization.model` to separate scenario groups:

| Tag | Scenarios |
| --- | --- |
| `authorization.model=RBAC` | admin role checks |
| `authorization.model=Customer Scope` | own-customer and cross-customer checks |
| `authorization.model=ABAC` | region, segment, and risk-level checks |
| `authorization.model=ReBAC` | relationship-manager and auditor checks |

Open Jaeger:

```powershell
kubectl port-forward svc/jaeger 16686:16686 -n observability
```

Then open `http://localhost:16686` and search for a printed trace id.

## Example Traces

The repository includes screenshots under `docs/assets` that show the main outcomes in Jaeger:

- Own customer account allowed: `docs/assets/external client own account.jpeg`
- Cross-customer access denied: `docs/assets/external client access denied.jpeg`
- Admin customer list allowed: `docs/assets/external client admin.jpeg`
