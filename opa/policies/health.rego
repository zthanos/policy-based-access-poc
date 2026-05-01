package envoy.authz

import rego.v1

allow if {
	method == "GET"
	path == ["health"]
}
