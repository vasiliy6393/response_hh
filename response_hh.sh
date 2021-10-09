#!/bin/sh
#  AUTHOR: Vasiliy Pogoreliy, vasiliy@pogoreliy.ru 

# Объявляем переменные чтобы скрипт работал на любом дистрибутиве
export PS="$(which ps)";
export JQ="jq --compact-output"; export CAT="$(which cat)";
export AWK="$(which awk)"; export GREP="$(which grep)";
export DATE="$(which date)"; export CURL="$(which curl)";
export SLEEP="$(which sleep)"; export KILL="$(which kill)";
export URL="https://api.hh.ru"; export LOG="/var/log/response_hh.log";
export CODE="$(cat /var/log/hh.code)"; # код генерируется другим скриптом
export HEADERS_AUTH="Authorization: Bearer $CODE";
export HEADERS_CONTENT_TYPE="Content-Type=multipart/form-data";
export LIMIT_EXCEEDED="Daily negotiations limit is exceeded";
export MSG="Здравствуйте. Прошу Вас рассмотреть моё резюме";
sys_admin=( "<specialization>" "<resume_id>" "$MSG <resume_name>" );
mechanic=( "<specialization>" "<resume_id>" "$MSG <resume_name>" );
cook=( "<specialization>" "<resume_id>" "$MSG <resume_name>" );

PID_FILE='/tmp/response_hh.pid';
if [[ -e "$PID_FILE" ]]; then
    LAST_PID="$($CAT "$PID_FILE")";
    if [[ "$LAST_PID" =~ ^[0-9]+$ ]]; then
        # Бывает остаются процессы-потомки, занимают место в списке процессов
        # и могут выполнить нежелательные действия. Скорее всего это связано с тем,
        # что циклы в BASH выполняются в отдельном процессе.
        # Убиваем все процессы, кроме списка исключений, если такие имеются.
        e="..."; # Добавьте своё
        $KILL -- -$($PS -o pid=,pgid=$LAST_PID,cmd= | $GREP -Pv "$e" |
                    $AWK '{print $1}' | $GREP -Pv "$$") > /dev/null 2>&1;
    fi
fi
echo "$$" > "$PID_FILE";

function WAIT(){
    startTime=$($DATE +%s)
    endTime=$($DATE -d "$1" +%s)
    timeToWait=$(($endTime-$startTime))
    $SLEEP $timeToWait;
}

function main(){
    # area=3 - Екатериньбург
    spec="$1";
    RESUME_ID="$2";
    MSG="$3";
    $CURL -s -H "$HEADERS_AUTH" "$URL/vacancies?specialization=$spec&area=3" |
    $JQ -c '.items[] | {id}' | $AWK -F\" '{print $4}' |
    while read vacancy_id; do
        # Если в файле содержится $vacancy_id
        # значит резюме уже отправляли, не будем зря отвлекать людей от работы
        if ! grep -Pq "^$vacancy_id$" "$LOG"; then
            RES_RESPONSE="$($CURL -H "$HEADERS_AUTH" -H "$HEADERS_CONTENT_TYPE" \
                 -s -X POST "$URL/negotiations" \
                 -F "vacancy_id=$vacancy_id" \
                 -F "resume_id=$RESUME_ID" \
                 -F "message=$MSG")";
            if echo "$RES_RESPONSE" | grep -Pq "$LIMIT_EXCEEDED"; then
                # Если дневной лимит превышен
                # Ждём 08:00 следующего дня.
                # Резюме отправлено не будет, но мне это не критично -
                # Одним больше, одним меньше - какая разница если дневной лимит пара сотен =)
                # Тем более оно всё равно будет отправлено со следующего прогона цикла.
                WAIT "08:00 next day";
            elif echo "$RES_RESPONSE" | grep -Pq "$ALREADY_APPLIED"; then
                continue;
            else
                [[ "a$RES_RESPONSE" != "a" ]] && echo "$RES_RESPONSE" >> $LOG;
                echo "$vacancy_id" >> $LOG;
            fi
        fi
    done
}

while true; do
    now="$($DATE +%-H)";
    if [[ "$now" -gt "20" ]]; then
        WAIT "08:00 next day"; # Не беспокоим людей в вечернее время
    elif [[ "$now" -lt "8" ]]; then
        WAIT "08:00"; # Не беспокоим ночью, дождёмся начала рабочего дня (08:00)
    fi
    main "${sys_admin[0]}" "${sys_admin[1]}" "${sys_admin[2]}"; $SLEEP 1h;
    main "${mechanic[0]}" "${mechanic[1]}" "${mechanic[2]}"; $SLEEP 1m;
    main "${cook[0]}" "${cook[1]}" "${cook[2]}"; $SLEEP 1m;
done
