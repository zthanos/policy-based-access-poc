package envoy.authz

import rego.v1

allow if {
	method == "GET"
	path == ["admin", "customers"]
	is_admin
	log_decision(true, sprintf("admin list access user=%s", [jwt.preferred_username]))
}
