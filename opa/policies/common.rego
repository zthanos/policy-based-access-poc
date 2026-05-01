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

log_decision(result, reason) if {
	print(sprintf("opa_decision allow=%v method=%s path=%s user=%s reason=%s", [
		result,
		method,
		http.path,
		object.get(jwt, "preferred_username", "anonymous"),
		reason,
	]))
}
