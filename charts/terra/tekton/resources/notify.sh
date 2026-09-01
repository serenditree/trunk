#!/usr/bin/env ash
if [[ -n "$(params.start)" ]]; then
    DURATION=$(($(date +%s) - $(params.start)))
    MINUTES=$((DURATION / 60))
    SECONDS=$((DURATION % 60))
    DURATION=" in ${MINUTES}m ${SECONDS}s"
fi

STATUS=$(echo -n "$(params.status)" | tr '[:upper:]' '[:lower:]')
TITLE="*PipelineRun \`$(params.run)\` ${STATUS}${DURATION}:*"

for _status in $@; do
    _status=${_status/Succeeded:/:green_heart: }
    _status=${_status/Failed:/:broken_heart: }
    DETAILS="${DETAILS}\n${_status/None:/:x: }"
done

if [[ -n "$(params.image-sha)" ]]; then
    DETAILS="${DETAILS}\n\n$(params.image-sha)"
fi

TERMINAL_DETAILS=$(
echo "${DETAILS}" | sed \
        -e "s/:green_heart:/💚/g" \
        -e "s/:broken_heart:/💔/g" \
        -e "s/:x:/❌/g"
)
echo -e "${TITLE}\n${TERMINAL_DETAILS}\n"

curl --request POST "${WEBHOOK}" \
    --header "Content-type: application/json" \
    --data "{\"text\":\"${TITLE}\n${DETAILS}\"}"
