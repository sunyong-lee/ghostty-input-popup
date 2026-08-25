# Reads slurped transcript records, reports the question the session is waiting
# on. Shared so the watcher's trigger and the popup's staleness check cannot
# disagree about what "waiting" means.
#
# An answer is recorded as a user tool_result, not an assistant block, so the
# last assistant block stays the AskUserQuestion even after it is answered.
# Looking only at assistant blocks therefore reports a settled question as
# pending — which is what made the popup appear just after answering.
. as $all
| ([$all[] | select(.type == "user") | .message.content[]?
    | select(.type == "tool_result") | .tool_use_id]) as $answered
| ([$all[] | select(.type == "assistant") | .message.content[]?
    | select(.type == "text" or (.type == "tool_use" and .name == "AskUserQuestion"))]
   | last) as $tail
| if $tail == null then
	{kind: "text", qid: "", nq: 0, body: "Waiting for your input."}
  elif $tail.type == "text" then
	{kind: "text", qid: "", nq: 0, body: ($tail.text[0:700])}
  elif ($answered | index($tail.id)) != null then
	{kind: "text", qid: "", nq: 0, body: "Answered."}
  else
	{kind: "question",
	 qid: $tail.id,
	 nq: ([$tail.input.questions[]?] | length),
	 questions: [$tail.input.questions[]?
	             | {qtext: .question,
	                choices: ([.options[]?.label] | to_entries
	                          | map("\(.key + 1). \(.value)"))}],
	 body: ([$tail.input.questions[]?
	         | .question + "\n"
	           + ([.options[]?.label] | to_entries
	              | map("  \(.key + 1). \(.value)") | join("\n"))]
	        | join("\n\n") | .[0:700])}
  end
