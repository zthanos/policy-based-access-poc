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

allow if {
	method == "GET"
	path == ["health"]
}

allow if {
	method == "GET"
	count(path) == 3
	path[0] == "customers"
	customer_id := path[1]
	path[2] == "accounts"
	is_admin
	log_decision(true, sprintf("admin customer access customer=%s", [customer_id]))
}

allow if {
	method == "GET"
	count(path) == 3
	path[0] == "customers"
	customer_id := path[1]
	path[2] == "accounts"
	"user" in roles
	customer_id == jwt.customer_id
	log_decision(true, sprintf("own customer access user=%s customer=%s", [jwt.preferred_username, customer_id]))
}

allow if {
	method == "GET"
	path == ["admin", "customers"]
	is_admin
	log_decision(true, sprintf("admin list access user=%s", [jwt.preferred_username]))
}

is_admin if {
	"admin" in roles
}

log_decision(result, reason) if {
	print(sprintf("opa_decision allow=%v method=%s path=%s user=%s reason=%s", [
		result,
		method,
		http.path,
		object.get(jwt, "preferred_username", "anonymous"),
		reason,
	]))
}
