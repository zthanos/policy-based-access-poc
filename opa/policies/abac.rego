package envoy.authz

import rego.v1

allow if {
	method == "GET"
	count(path) == 3
	path[0] == "customers"
	customer_id := path[1]
	path[2] == "accounts"
	"relationship_manager" in roles
	customer := customer_attributes(customer_id)
	user_region == customer.region
	customer.segment == "corporate"
	request_risk_level != "high"
	log_decision(true, sprintf("abac relationship manager access user=%s customer=%s region=%s segment=%s risk=%s", [
		username,
		customer_id,
		customer.region,
		customer.segment,
		request_risk_level,
	]))
}
