#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL="${API_BASE_URL:-http://localhost:8080}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_FIXTURE="$SCRIPT_DIR/../docs/product-design.md"
COOKIE_JAR="$(mktemp)"
OTHER_COOKIE_JAR="$(mktemp)"
trap 'rm -f "$COOKIE_JAR" "$OTHER_COOKIE_JAR"' EXIT

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

json_request() {
  local method="$1" path="$2" payload="$3" expected="$4" cookie="${5:-$COOKIE_JAR}"
  local raw
  if [ "$method" = "GET" ]; then
    raw="$(curl --silent --show-error --write-out $'\n%{http_code}' -b "$cookie" \
      "$API_BASE_URL$path")"
  else
    raw="$(curl --silent --show-error --write-out $'\n%{http_code}' -b "$cookie" \
      -H 'Content-Type: application/json' -X "$method" --data "$payload" \
      "$API_BASE_URL$path")"
  fi
  HTTP_STATUS="${raw##*$'\n'}"
  HTTP_BODY="${raw%$'\n'*}"
  [ "$HTTP_STATUS" = "$expected" ] || fail "$method $path returned $HTTP_STATUS, expected $expected: $HTTP_BODY"
}

assert_json() {
  local label="$1" expression="$2" body="$3"
  jq -e "$expression" >/dev/null <<<"$body" || fail "$label: $body"
  pass "$label"
}

register_and_login() {
  local handle="$1" cookie="$2"
  local credentials register
  register="$(jq -cn --arg handle "$handle" --arg email "$handle@example.test" \
    '{handle:$handle,displayName:"Product Smoke",email:$email,password:"LocalSmokeOnly123!"}')"
  credentials="$(jq -cn --arg email "$handle@example.test" \
    '{handleOrEmail:$email,password:"LocalSmokeOnly123!"}')"
  curl --fail --silent --show-error -H 'Content-Type: application/json' --data "$register" \
    "$API_BASE_URL/api/auth/register" >/dev/null
  curl --fail --silent --show-error -c "$cookie" -H 'Content-Type: application/json' \
    --data "$credentials" "$API_BASE_URL/api/auth/login" >/dev/null
}

product_payload() {
  local type="$1" title="$2" price="$3" status="$4" configuration="$5"
  jq -cn --arg type "$type" --arg title "$title" --argjson price "$price" \
    --arg status "$status" --argjson configuration "$configuration" \
    '{type:$type,title:$title,subtitle:("Configured " + $title),description:("End-to-end " + $title),callToAction:"Get access",thumbnailStyle:"preview",priceSubunits:$price,status:$status,position:10,configuration:$configuration}'
}

create_product() {
  local type="$1" title="$2" price="$3" status="$4" configuration="$5"
  local payload
  payload="$(product_payload "$type" "$title" "$price" "$status" "$configuration")"
  json_request POST /api/v1/products "$payload" 201
  CREATED_BODY="$HTTP_BODY"
  CREATED_ID="$(jq -er '.id' <<<"$CREATED_BODY")"
}

curl --fail --silent --show-error "$API_BASE_URL/health" >/dev/null
pass "API health"

RUN_KEY="$(date +%s)_$$"
HANDLE="products_$RUN_KEY"
OTHER_HANDLE="other_$RUN_KEY"
register_and_login "$HANDLE" "$COOKIE_JAR"
register_and_login "$OTHER_HANDLE" "$OTHER_COOKIE_JAR"
pass "two isolated creator sessions"

# A browser retry after a timeout must not create a duplicate draft. This uses a
# separate draft so the public eight-product count below remains deterministic.
retry_config='{"schemaVersion":1,"deliveryMode":"upload","redirectUrl":""}'
retry_payload="$(product_payload digital-download "Retry draft $RUN_KEY" 19900 draft "$retry_config")"
retry_key="product-smoke-$RUN_KEY"
first_retry="$(curl --silent --show-error --write-out $'\n%{http_code}' -b "$COOKIE_JAR" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $retry_key" \
  --data "$retry_payload" "$API_BASE_URL/api/v1/products")"
second_retry="$(curl --silent --show-error --write-out $'\n%{http_code}' -b "$COOKIE_JAR" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $retry_key" \
  --data "$retry_payload" "$API_BASE_URL/api/v1/products")"
first_retry_status="${first_retry##*$'\n'}"
second_retry_status="${second_retry##*$'\n'}"
first_retry_body="${first_retry%$'\n'*}"
second_retry_body="${second_retry%$'\n'*}"
[ "$first_retry_status" = "201" ] || fail "first idempotent create returned $first_retry_status: $first_retry_body"
[ "$second_retry_status" = "201" ] || fail "retried idempotent create returned $second_retry_status: $second_retry_body"
[ "$(jq -er '.id' <<<"$first_retry_body")" = "$(jq -er '.id' <<<"$second_retry_body")" ] \
  || fail "same Idempotency-Key created two products"
pass "retried product creation is idempotent"

digital_config='{"schemaVersion":1,"deliveryMode":"upload","redirectUrl":""}'
create_product digital-download "Download $RUN_KEY" 49900 draft "$digital_config"
DIGITAL_ID="$CREATED_ID"
digital_publish="$(product_payload digital-download "Download $RUN_KEY" 49900 published "$digital_config")"
json_request PATCH "/api/v1/products/$DIGITAL_ID" "$digital_publish" 409
json_request GET "/api/v1/products/$DIGITAL_ID/configuration" '' 200
assert_json "failed publish rolls back to draft" '.status == "draft"' "$HTTP_BODY"

upload_raw="$(curl --silent --show-error --write-out $'\n%{http_code}' -b "$COOKIE_JAR" \
  -F "file=@$UPLOAD_FIXTURE;type=text/markdown" \
  "$API_BASE_URL/api/v1/products/$DIGITAL_ID/files?kind=download")"
upload_status="${upload_raw##*$'\n'}"
upload_body="${upload_raw%$'\n'*}"
[ "$upload_status" = "201" ] || fail "digital upload returned $upload_status: $upload_body"
DIGITAL_FILE_ID="$(jq -er '.id' <<<"$upload_body")"
json_request PATCH "/api/v1/products/$DIGITAL_ID" "$digital_publish" 200
assert_json "digital upload product publishes" '.status == "published" and (.files | length) == 1' "$HTTP_BODY"

lead_config='{"schemaVersion":1,"deliveryMode":"redirect","redirectUrl":"https://private.example.test/free-guide","collectName":true,"collectEmail":true,"collectPhone":true,"consentText":"I agree to receive this resource."}'
create_product lead-magnet "Lead $RUN_KEY" 0 published "$lead_config"
LEAD_ID="$CREATED_ID"

meeting_config='{"schemaVersion":1,"location":"phone","locationDetails":"Private dial-in","timezone":"Asia/Kolkata","durationMinutes":60,"maxAttendees":1,"minNoticeHours":12,"bufferMinutes":15,"slots":[{"startsAt":"2035-01-10T04:30:00Z","endsAt":"2035-01-10T05:30:00Z"}]}'
create_product meeting "Meeting $RUN_KEY" 99900 published "$meeting_config"
MEETING_ID="$CREATED_ID"
assert_json "meeting slot receives a stable normalized id" '.meeting_slots[0].id > 0 and .configuration.slots[0].id > 0' "$CREATED_BODY"

webinar_config='{"schemaVersion":1,"location":"zoom","timezone":"Asia/Kolkata","durationMinutes":60,"capacity":100,"sessions":[{"startsAt":"2035-02-10T04:30:00Z","endsAt":"2035-02-10T05:30:00Z","capacity":100,"joinUrl":"https://private.example.test/webinar-room"}]}'
create_product webinar "Webinar $RUN_KEY" 79900 published "$webinar_config"
WEBINAR_ID="$CREATED_ID"
assert_json "webinar session is normalized" '.webinar_sessions[0].id > 0 and .configuration.sessions[0].id > 0' "$CREATED_BODY"

course_config='{"schemaVersion":1,"dripDays":2,"modules":[{"title":"Plan","description":"Private module notes","position":0,"lessons":[{"title":"Choose an offer","description":"Private lesson content","videoUrl":"https://private.example.test/course-video","position":0}]}]}'
create_product course "Course $RUN_KEY" 149900 published "$course_config"
COURSE_ID="$CREATED_ID"
assert_json "course module and lesson receive normalized ids" '.course_modules[0].id > 0 and .course_modules[0].lessons[0].id > 0' "$CREATED_BODY"

membership_config='{"schemaVersion":1,"benefits":["Weekly workshop","Template library"],"memberBenefits":"Weekly workshop\nTemplate library","welcomeMessage":"Private welcome message","plans":[{"name":"Monthly","amountSubunits":79900,"interval":"monthly","intervalCount":1}]}'
create_product membership "Membership $RUN_KEY" 79900 published "$membership_config"
MEMBERSHIP_ID="$CREATED_ID"
assert_json "membership plan receives normalized id" '.payment_plans[0].id > 0 and .configuration.plans[0].id > 0' "$CREATED_BODY"

fulfillment_config='{"schemaVersion":1,"turnaroundDays":3,"deliveryFormat":"file-upload","buyerInstructions":"Private creator workflow","checkoutFields":[{"label":"Describe your project","fieldType":"textarea","required":true,"position":0},{"label":"Reference URL","fieldType":"url","required":false,"position":1}]}'
create_product fulfillment "Service $RUN_KEY" 249900 published "$fulfillment_config"
FULFILLMENT_ID="$CREATED_ID"
assert_json "checkout questions receive normalized ids" '(.checkout_fields | length) == 2 and .configuration.checkoutFields[0].id > 0' "$CREATED_BODY"

community_config='{"schemaVersion":1,"platform":"slack","accessUrl":"https://private.example.test/slack-invite","benefits":["Private channel"],"memberBenefits":"Private channel","welcomeMessage":"Private community welcome"}'
create_product community "Community $RUN_KEY" 59900 published "$community_config"
COMMUNITY_ID="$CREATED_ID"

for product_id in "$DIGITAL_ID" "$LEAD_ID" "$MEETING_ID" "$WEBINAR_ID" \
  "$COURSE_ID" "$MEMBERSHIP_ID" "$FULFILLMENT_ID" "$COMMUNITY_ID"; do
  json_request GET "/api/public/$HANDLE/products/$product_id" '' 200
  assert_json "public product $product_id has only a safe projection" \
    'has("public_configuration") and (has("configuration_json") | not)' "$HTTP_BODY"
  if grep -Eqi 'private\.example|redirectUrl|object_key|join_url|accessUrl|buyerInstructions|welcomeMessage|video_url|Private module notes|Private lesson content|Private creator workflow' <<<"$HTTP_BODY"; then
    fail "public product $product_id leaked private configuration: $HTTP_BODY"
  fi
done

json_request GET "/api/public/$HANDLE" '' 200
assert_json "public collection contains all eight configured products" '.products | length == 8' "$HTTP_BODY"
if grep -Eqi 'private\.example|configuration_json|object_key|join_url|accessUrl|buyerInstructions|welcomeMessage|video_url|Private module notes|Private lesson content|Private creator workflow' <<<"$HTTP_BODY"; then
  fail "public collection leaked private configuration: $HTTP_BODY"
fi
pass "public collection excludes private configuration"

wrong_type_payload="$(product_payload course "Download $RUN_KEY" 49900 published "$course_config")"
json_request PATCH "/api/v1/products/$DIGITAL_ID" "$wrong_type_payload" 409
pass "product type is immutable"

json_request GET "/api/v1/products/$DIGITAL_ID/configuration" '' 404 "$OTHER_COOKIE_JAR"
json_request DELETE "/api/v1/products/$DIGITAL_ID/files/$DIGITAL_FILE_ID" '{}' 404 "$OTHER_COOKIE_JAR"
pass "cross-creator product and file access is hidden"

json_request DELETE "/api/v1/products/$DIGITAL_ID/files/$DIGITAL_FILE_ID" '{}' 409
pass "last required file of a published download is protected"

printf '\nProduct-type smoke test passed for creator %s.\n' "$HANDLE"
printf 'Verified product ids: %s %s %s %s %s %s %s %s\n' \
  "$DIGITAL_ID" "$LEAD_ID" "$MEETING_ID" "$WEBINAR_ID" \
  "$COURSE_ID" "$MEMBERSHIP_ID" "$FULFILLMENT_ID" "$COMMUNITY_ID"
