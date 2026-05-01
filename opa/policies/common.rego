package envoy.authz

import rego.v1

default allow := false

http := input.attributes.request.http

method := http.method

path := parsed_path if {
	raw_path := split(http.path, "?")[0]
	trimmed := trim(raw_path, "/")
	trimmed == ""
	parsed_path := []
} else := parsed_path if {
	raw_path := split(http.path, "?")[0]
	trimmed := trim(raw_path, "/")
	trimmed != ""
	parsed_path := split(trimmed, "/")
}

jwt := payload if {
	header := http.headers["x-jwt-payload"]
	raw := base64url.decode(header)
	payload := json.unmarshal(raw)
} else := payload if {
	auth_header := http.headers.authorization
	startswith(lower(auth_header), "bearer ")
	token := substring(auth_header, 7, -1)
	[_, payload, _] := io.jwt.decode(token)
}

roles := object.get(jwt, "roles", [])

is_admin if {
	"admin" in roles
}

username := object.get(jwt, "preferred_username", "anonymous")

request_header(name, fallback) := value if {
	value := object.get(http.headers, name, fallback)
}

request_risk_level := request_header("x-risk-level", "normal")

request_purpose := request_header("x-purpose", "")

request_channel := request_header("x-channel", "web")

request_time_window := request_header("x-time-window", "business_hours")

request_device_trust := request_header("x-device-trust", "trusted")

user_department := object.get(jwt, "department", "")

user_region := object.get(jwt, "region", "")

user_customer_segment := object.get(jwt, "customer_segment", "")

customer_attributes(customer_id) := attrs if {
	attrs := data.customers[customer_id]
}

log_decision(result, reason) if {
	print(sprintf("opa_decision allow=%v method=%s path=%s user=%s reason=%s", [
		result,
		method,
		http.path,
		username,
		reason,
	]))
}
