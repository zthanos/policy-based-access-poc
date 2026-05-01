package envoy.authz

import rego.v1

allow if {
	method == "GET"
	count(path) == 3
	path[0] == "customers"
	customer_id := path[1]
	path[2] == "accounts"
	customer_id in object.get(data.relationships.relationship_manager_of, username, [])
	request_risk_level != "high"
	log_decision(true, sprintf("rebac relationship manager access user=%s customer=%s", [username, customer_id]))
}

allow if {
	method == "GET"
	count(path) == 3
	path[0] == "customers"
	customer_id := path[1]
	path[2] == "accounts"
	customer_id in object.get(data.relationships.auditor_of, username, [])
	request_purpose == "audit"
	request_risk_level != "high"
	log_decision(true, sprintf("rebac auditor access user=%s customer=%s purpose=%s", [username, customer_id, request_purpose]))
}
