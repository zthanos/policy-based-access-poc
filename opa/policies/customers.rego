package envoy.authz

import rego.v1

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
