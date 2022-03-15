#!/bin/sh

#  AUTHOR: Vasiliy Pogoreliy, vasiliy@pogoreliy.ru 
PATH="/my_bin:$PATH";

# Паралельно начал делать веб-интерфейс для скрипта
# Исходники веб-интерфейса скорее всего выложены не будут
# Но будет оставлена ссылка в этом исходнике

export SED="$(which sed)";
for i in tr jq ps cat awk grep head tail date sleep kill curl sleep; do
    eval $(echo "export $(echo "$i" | $SED 's/.*/\U&/g')=\$(which $i);");
done

if [[ ! -z $1 ]]; then export USER="$1"; else echo "Field \"user\" is empty. Exiting."; exit; fi

export JQc="$(which jq) --compact-output";
export TELEGRAM_SEND="$(which telegram_send.sh)"
export URL="https://api.hh.ru"; export LOG="/var/log/hh/response_hh_$USER.log";
export CODE="$(cat /var/log/hh/hh_$USER.code)"; # код генерируется другим скриптом
export HEADERS_AUTH="Authorization: Bearer $CODE";
export HEADERS_CONTENT_TYPE="Content-Type=multipart/form-data";
export LIMIT_EXCEEDED="Daily negotiations limit is exceeded";
export ALREADY_APPLIED="Already applied";
export MSG="Здравствуйте. Прошу Вас рассмотреть моё резюме";

touch "$LOG";

PID_FILE="/tmp/response_hh_$USER.pid";
if [[ -e "$PID_FILE" ]]; then
    LAST_PID="$($CAT "$PID_FILE")";
    if [[ "$LAST_PID" =~ ^[0-9]+$ ]]; then
        $KILL $LAST_PID > /dev/null 2>&1;
    fi
fi
echo "$$" > "$PID_FILE";

function WAIT(){
    startTime=$($DATE +%s)
    endTime=$($DATE -d "$1" +%s)
    timeToWait=$(($endTime-$startTime))
    timeToWait_minutes="$(($timeToWait/60)).$(($timeToWait%60))";
    for i in $(eval echo {0..$timeToWait}); do
        startTime=$($DATE +%s)
        endTime=$($DATE -d "$1" +%s)
        timeToWait=$(($endTime-$startTime))
        timeToWait_min="$(($timeToWait/60))";
        timeToWait_sec="$(($timeToWait%60))";
        if [[ "$timeToWait_min" -gt "60" ]]; then
            timeToWait_hour="$(($timeToWait_min/60))";
            timeToWait_min="$(($timeToWait_min%60))";
        fi
        if echo "$timeToWait_hour" | $GREP -Pq '^[0-9]$'; then
            timeToWait_hour="0$timeToWait_hour:";
        else
            timeToWait_hour="$timeToWait_hour:";
        fi
        if echo "$timeToWait_min" | $GREP -Pq '^[0-9]$'; then
            timeToWait_min="0$timeToWait_min:";
        else
            timeToWait_min="$timeToWait_min:";
        fi
        if echo "$timeToWait_sec" | $GREP -Pq '^[0-9]$'; then
            timeToWait_sec="0$timeToWait_sec";
        else
            timeToWait_sec="$timeToWait_sec";
        fi
        echo -en "  скрипт запустится через: $timeToWait_hour$timeToWait_min$timeToWait_sec     \r";
        sleep 1;
    done
}

function SEND_RESUME(){
    # Функция отправки отклика
    RESUME_ID="$1";
    vacancy_id_address="$2";
    vacancy_address="$($SED 's/^[0-9]\+ \?//' <<< "$vacancy_id_address")";
    vacancy_address="$($SED 's/ \?[Уу]лица \?\| \?[Пп]ереулок \?\| \?[Тт]упик \?\| \?[Пп]роспект \?//' <<< "$vacancy_address")";
    vacancy_address="$($SED 's/[а-яА-ЯёЁ]\+ район//' <<< "$vacancy_address")";
    vacancy_address="$($SED 's/микрорайон [а-яА-ЯёЁ]\+//' <<< "$vacancy_address")";
    vacancy_address="$($SED 's/, \?//g' <<< "$vacancy_address")";
    vacancy_id="$($AWK '{print $1}' <<< "$vacancy_id_address")";
    # Если в файле содержится $vacancy_id
    # значит резюме уже отправляли, не будем зря отвлекать людей от работы
    if ! $GREP -Pq "$vacancy_id" <<< "$LOG"; then
        # Проверка адреса по списку улиц, в будущем скорее всего уберу
        if [[ "a$vacancy_address" != "a" ]]; then # Неуказанные адреса игнорим
            if $GREP -Piq "$vacancy_address" "/var/log/hh/hh_streets.lst"; then
            RES_RESPONSE="$($CURL -H "$HEADERS_AUTH" -H "$HEADERS_CONTENT_TYPE" \
                -s -X POST "$URL/negotiations" -F "vacancy_id=$vacancy_id" \
                                               -F "resume_id=$RESUME_ID" -F "message=$MSG")";
                if echo "$RES_RESPONSE" | $GREP -Pq "$LIMIT_EXCEEDED"; then
                    # Если дневной лимит превышен
                    # Ждём 08:00 следующего дня.
                    # Резюме отправлено не будет, но мне это не критично -
                    # Одним больше, одним меньше - какая разница если дневной
                    # лимит пара сотен =)
                    # Тем более оно всё равно будет отправлено со следующего
                    # прогона цикла.
                    echo "$($DATE): $vacancy_id wait next day (limit_exceeded)";
                    echo "$($DATE): $vacancy_id wait next day (limit_exceeded)" >> $LOG;
                    WAIT "08:00 next day";
                elif echo "$RES_RESPONSE" | $GREP -Pq "$ALREADY_APPLIED"; then
                    echo "$($DATE): $vacancy_id not send (already_applied)";
                    # echo "$($DATE): $vacancy_id not send (already_applied)" >> $LOG;
                    continue;
                elif [[ "a$RES_RESPONSE" != "a" ]]; then
                    echo "$RES_RESPONSE" >> $LOG;
                else
                    echo "$RES_RESPONSE";
                    echo "$($DATE): vacancy_id=$vacancy_id resume_id=$RESUME_ID message=$MSG" >> $LOG;
                fi
            fi
        fi
    fi
}

function FATAL_ERROR(){
    $TELEGRAM_SEND "$0: ошибка, скрипт остановлен" > /dev/null 2>&1;
    exit;
}

resume_list="$($CURL -H "$HEADERS_AUTH" -s -X GET "$URL/resumes/mine" |
                   $JQc '.items[] | {id, title, access}' |
                   $AWK -F\" '{print $4" \""$8"\" "$20}' | 
                   $GREP -Pv 'выбранным компаниям|по прямой ссылке|никому' |
                   $SED 's/^\([^ ]\+\) "\([^"]\+\)".*/\1 \2/')";

cycle=0;
repeat="false";
while true; do
    max_pages="$2";
    if [[ "$cycle" -ge "200" ]]; then
        cycle="0";
        repeat="true";
        sleep 5m;
        resume_list="$($CURL -H "$HEADERS_AUTH" -s -X GET "$URL/resumes/mine" |
                           $JQc '.items[] | {id, title, access}' |
                           $AWK -F\" '{print $4" \""$8"\" "$20}' | 
                           $GREP -Pv 'выбранным компаниям|по прямой ссылке|никому' |
                           $SED 's/^\([^ ]\+\) "\([^"]\+\)".*/\1 \2/')";
    fi
    if [[ ! -z $max_pages ]] && [[ "$cycle" -gt "$max_pages" ]]; then break; fi
    now="$($DATE +%-H)";
    if [[ "$now" -ge "20" ]]; then
        echo "Wait next day; PID=$$;" >> $LOG;
        WAIT "08:00 next day"; # Не беспокоим людей в вечернее время
    elif [[ "$now" -lt "8" ]]; then
        echo "Wait 08:00; PID=$$;" >> $LOG;
        WAIT "08:00"; # Не беспокоим ночью, дождёмся начала рабочего дня (08:00)
    fi
    if [[ "$cycle" -eq "0" ]] && [[ "$repeat" != "true" ]]; then
        echo "Started: DATE=$(date +"%d.%m.%Y | %H:%M:%S"); PID=$$;" >> $LOG;
        $TELEGRAM_SEND "$0: начало рассылки резюме" > /dev/null 2>&1;
    fi

    echo "$resume_list" | while read r; do
        rid="$(echo "$r" | $AWK '{print $1}')";
        rname="$(echo "$r" | $SED 's/^[0-9a-zA-Z]\+ //')";
        resume=("$rid" "$MSG \"$rname\"." );
        RESUME_ID="${resume[0]}";
        MSG="${resume[1]}";
        spec_1="$(echo "$MSG" | $SED 's/.*рассмотреть моё резюме "\([^"]\+\)"\./\1/')";
        spec_2="$(echo "$spec_1" | $SED 's/\-/ /')";
        spec="$(for s in $spec_2; do
            echo -en "specialization=";
            s="$(echo -en "$s" | $SED 's/^.//')";
            $CURL -H "$HEADERS_AUTH" -s -X GET "$URL/specializations" | jq |
                $GREP -P -B1 "$s" | $GREP -P '"id":' | $SED 's/.*"id": "\([0-9\.]\+\)",/\1/' |
                $TR "\n" "&";
        done)";
        per_page="per_page=10";
        page="page=$cycle";
        metro="metro=48.261&metro=48.262&metro=48.263";
        premium="premium=true";
        $CURL -H "$HEADERS_AUTH" -s -X GET "$URL/vacancies?$spec&$per_page&$page&$metro&$premium" |
            $JQc '.items[] | {id, address}' | $AWK -F\" '{print $4" "$14}' |
                while read vacancy_id_address; do
                    if grep -Piq 'грузчик' <<< "$vacancy_id_address"; then
                        if [[ "$USER" == "vasiliy" ]]; then
                            SEND_RESUME "$RESUME_ID" "$vacancy_id_address" || FATAL_ERROR;
                        fi
                    else
                        SEND_RESUME "$RESUME_ID" "$vacancy_id_address" | FATAL_ERROR;
                    fi
                done
    done
    cycle=$(($cycle+1));
done
