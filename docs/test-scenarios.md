# Test Scenarios

| Scenario | User | Token | Expected |
| --- | --- | --- | --- |
| `GET /health` | anonymous | none | `200` |
| `GET /customers/CUST-001/accounts` | `user1` | valid | `200` |
| `GET /customers/CUST-002/accounts` | `user1` | valid | `403` |
| `GET /admin/customers` | `user1` | valid | `403` |
| `GET /admin/customers` | `admin` | valid | `200` |
| `GET /customers/CUST-001/accounts` | anonymous | none | `401` |

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
