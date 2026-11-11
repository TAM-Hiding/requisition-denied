class_name AdministrativeSession
extends Node
## Facility-owned records. Subscribers receive facts and have no gameplay authority.
signal event_published(event: Dictionary)
const CATALOG := {
	&"light": {"name": "Maintenance light source", "description": "Portable illumination for assigned maintenance.", "eligibility": "Available for review", "outcome": "APPROVED", "reason": "Allocation approved. Delivery has not been scheduled."},
	&"tool": {"name": "Auxiliary tool allocation", "description": "One supplementary maintenance tool.", "eligibility": "Available for review", "outcome": "DENIED", "reason": "Current equipment allocation has been deemed sufficient. Additional justification is not required or accepted."},
	&"access": {"name": "Access authorization review", "description": "Review of current personnel access.", "eligibility": "Available for review", "outcome": "DENIED", "reason": "No expansion of assigned access is authorized."},
}
enum RequestStatus { SUBMITTED, APPROVED, DENIED, FULFILLED }
var text_brightness := 0.82
var _messages: Array[Dictionary] = []
var _requests: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _elapsed_seconds := 0.0

func _ready() -> void:
	_add_message("MSG-001", "Facility Administration", "Personnel Orientation",
		"Otis, your presence in the Facility has been recorded. Proceed with your assigned work. Orientation is considered complete upon receipt of this notice.")
	_add_message("MSG-002", "Maintenance Administration", "Equipment Allocation Procedures",
		"Issued equipment remains Facility property. Returning a wrench to the wrong drawer counts as an unauthorized departmental transfer.")
	_add_message("MSG-003", "Security Administration", "Barrier Operating Requirements",
		"Keep powered barrier paths clear. A barrier that has stopped moving may resume without further administrative notice.")

func _add_message(id: String, sender: String, subject: String, body: String) -> void:
	_messages.append({"id": id, "sender": sender, "subject": subject, "body": body,
		"time_ms": elapsed_ms(), "read": false, "event_id": &""})

func _physics_process(delta: float) -> void:
	_elapsed_seconds += delta

func elapsed_ms() -> int:
	return roundi(_elapsed_seconds * 1000)

func messages() -> Array[Dictionary]:
	return _messages.duplicate(true)

func unread_count() -> int:
	var count := 0
	for message in _messages:
		if not message.read:
			count += 1
	return count

func read_message(id: String) -> Dictionary:
	for message in _messages:
		if message.id == id:
			message.read = true
			return message.duplicate(true)
	return {}

func requests() -> Array[Dictionary]:
	return _requests.duplicate(true)

func events() -> Array[Dictionary]:
	return _events.duplicate(true)

func publish_event(type: StringName, source: StringName, context: Dictionary = {}) -> void:
	var event := {"id": "EV-%04d" % (_events.size() + 1), "type": type, "source": source,
		"time_ms": elapsed_ms(), "context": context.duplicate(true)}
	_events.append(event)
	event_published.emit(event.duplicate(true))

func submit(catalog_id: StringName, terminal_id: StringName) -> Dictionary:
	if not CATALOG.has(catalog_id):
		return {}
	var entry: Dictionary = CATALOG[catalog_id]
	var request := {"id": "RQ-%04d" % (_requests.size() + 1), "catalog_id": catalog_id,
		"name": entry.name, "time_ms": elapsed_ms(), "status": RequestStatus.SUBMITTED, "reason": ""}
	_requests.append(request)
	request.status = RequestStatus[entry.outcome]
	request.reason = entry.reason
	publish_event(&"REQUISITION_SUBMITTED", terminal_id, {
		"request_id": request.id, "catalog_id": catalog_id, "status": request.status})
	return request.duplicate(true)
