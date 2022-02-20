#!/bin/sh
#  AUTHOR: Vasiliy Pogoreliy, vasiliy@pogoreliy.ru 
PATH="/my_bin:$PATH";

# Объявляем переменные чтобы скрипт работал на любом дистрибутиве
# Хотя мне это не особо актуально, я всегда выбираю Arch-based дистры

export SED="$(which sed)";

for i in ps cat awk grep head tail date sleep kill curl sleep; do
    eval $(echo "export $(echo "$i" | $SED 's/.*/\U&/g')=\$(which $i);");
done

if [[ ! -z $1 ]]; then USER="$1"; else echo "User \"$1\" not found. Exiting."; exit; fi

export JQ="$(which jq) --compact-output";
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

function main(){
    # Если удастся договориться с Google, Яндекс или 2gis, в этой функции будет добавлено определение
    # расстояния до места работы
    # Как временное решение использую список улиц, но этот вариант мне не нравится, буду искать решение лучше

    # другой способ отправки резюме - если в будущем захочу к нему вернуться будет проще это сделать
    # area=3 - Екатериньбург
    # $CURL -s -H "$HEADERS_AUTH" "$URL/vacancies?specialization=$spec&area=3" |
    # $JQ -c '.items[] | {id}' | $AWK -F\" '{print $4}' |
    RESUME_ID="$1";
    MSG="$2";
    $CURL -H "$HEADERS_AUTH" -s -X GET "$URL/resumes/$RESUME_ID/similar_vacancies" |
    $JQ -c '.items[] | {id, address}' | $AWK -F\" '{print $4" "$14}' | $HEAD -n 10 |
    while read vacancy_id_address; do
        vacancy_address="$($SED 's/^[0-9]\+ \?//' <<< "$vacancy_id_address")";
        vacancy_address="$($SED 's/ \?[Уу]лица \?\| \?[Пп]ереулок \?\| \?[Тт]упик \?\| \?[Пп]роспект \?//' <<< "$vacancy_address")";
        vacancy_address="$($SED 's/[а-яА-ЯёЁ]\+ район//' <<< "$vacancy_address")";
        vacancy_address="$($SED 's/микрорайон [а-яА-ЯёЁ]\+//' <<< "$vacancy_address")";
        vacancy_address="$($SED 's/, \?//g' <<< "$vacancy_address")";
        vacancy_id="$($AWK '{print $1}' <<< "$vacancy_id_address")";
        # Если в файле содержится $vacancy_id
        # значит резюме уже отправляли, не будем зря отвлекать людей от работы
        if ! $AWK '{print $2}' "$LOG" | $GREP -Pq "^$vacancy_id$"; then
            if [[ "a$vacancy_address" != "a" ]] && $GREP -Piq "$vacancy_address" "/var/log/hh/hh_streets.lst"; then
                RES_RESPONSE="$($CURL -H "$HEADERS_AUTH" -H "$HEADERS_CONTENT_TYPE" \
                    -s -X POST "$URL/negotiations" -F "vacancy_id=$vacancy_id" \
                                                   -F "resume_id=$RESUME_ID" -F "message=$MSG")";
                    [[ "a$RES_RESPONSE" != "a" ]] && echo "$RES_RESPONSE" >> $LOG;
                echo "$($DATE): vacancy_id=$vacancy_id resume_id=$RESUME_ID message=$MSG";
                echo "$($DATE): $vacancy_id" >> $LOG;
                if echo "$RES_RESPONSE" | $GREP -Pq "$LIMIT_EXCEEDED"; then
                    # Если дневной лимит превышен
                    # Ждём 08:00 следующего дня.
                    # Резюме отправлено не будет, но мне это не критично -
                    # Одним больше, одним меньше - какая разница если дневной
                    # лимит пара сотен =)
                    # Тем более оно всё равно будет отправлено со следующего
                    # прогона цикла.
                    WAIT "08:00 next day";
                elif echo "$RES_RESPONSE" | $GREP -Pq "$ALREADY_APPLIED"; then
                    continue;
                fi
            else
                echo "$($DATE): $vacancy_id" >> $LOG;
            fi
        fi
    done
}

resume_list="$($CURL -H "$HEADERS_AUTH" -s -X GET "$URL/resumes/mine" |
                   $JQ -c '.items[] | {id, title, access}' |
                   $AWK -F\" '{print $4" "$8" "$20}' | 
                   $GREP -P 'видно всем компаниям' | $SED 's/ видно всем компаниям.*//')";

cycle=0;
while true; do
    if [[ ! -z $2 ]] && [[ "$cycle" == "$2" ]]; then exit; fi
    now="$($DATE +%-H)";
    if [[ "$now" -gt "20" ]]; then
        WAIT "08:00 next day"; # Не беспокоим людей в вечернее время
    elif [[ "$now" -lt "8" ]]; then
        WAIT "08:00"; # Не беспокоим ночью, дождёмся начала рабочего дня (08:00)
    fi
    if [[ "$cycle" -eq "0" ]]; then
        $TELEGRAM_SEND "$0: начало рассылки резюме" > /dev/null 2>&1;
    fi

    echo "$resume_list" | while read r; do
        rid="$(echo "$r" | $AWK '{print $1}')";
        rname="$(echo "$r" | $SED 's/^[0-9a-zA-Z]\+ //')";
        resume=("$rid" "$MSG \"$rname\"." );
        main "${resume[0]}" "${resume[1]}" || FATAL_ERROR="true"; $SLEEP 5;
    done

    if [[ ! -z $FATAL_ERROR ]]; then
        $TELEGRAM_SEND "$0: ошибка, скрипт остановлен" > /dev/null 2>&1;
        exit;
    fi
    if [[ ! -z $FATAL_ERROR ]]; then
        $TELEGRAM_SEND "$0: ошибка, скрипт остановлен" > /dev/null 2>&1;
        exit;
    fi
    cycle=$(($cycle+1));
done
