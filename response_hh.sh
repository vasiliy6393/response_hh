#!/bin/sh
# AUTHOR: Vasiliy Pogoreliy, vasiliy@pogoreliy.ru 

# Объявляем переменные чтобы скрипт работал на любом дистрибутиве
USER="%user%";

export PS="$(which ps)";
export JQ="jq --compact-output"; export CAT="$(which cat)";
export AWK="$(which awk)"; export GREP="$(which grep)";
export HEAD="$(which head)"; export TAIL="$(which tail)";
export DATE="$(which date)"; export CURL="$(which curl)";
export SLEEP="$(which sleep)"; export KILL="$(which kill)";
export URL="https://api.hh.ru"; export LOG="/var/log/hh/response_hh_$USER.log";
export CODE="$(cat /var/log/hh/hh_$USER.code)"; # код генерируется другим скриптом
export HEADERS_AUTH="Authorization: Bearer $CODE";
export HEADERS_CONTENT_TYPE="Content-Type=multipart/form-data";
export LIMIT_EXCEEDED="Daily negotiations limit is exceeded";
export ALREADY_APPLIED="Already applied";
export MSG="Здравствуйте. Прошу Вас рассмотреть моё резюме";

PID_FILE="/tmp/response_hh_$USER.pid";
if [[ -e "$PID_FILE" ]]; then
    LAST_PID="$($CAT "$PID_FILE")";
    if [[ "$LAST_PID" =~ ^[0-9]+$ ]]; then
        # Бывает остаются процессы-потомки, занимают место в списке процессов
        # и могут выполнить нежелательные действия. Скорее всего это связано с тем,
        # что циклы в bash выполняются в отдельном процессе.
        # Убиваем все процессы, кроме списка исключений, если такие имеются.
        e="telegram_main\.sh|fs_screensaver\.sh|mouse_move_kbrd\.sh";
        e="$e|mail_to_php_cron\.sh|nvidia-settings|xfwm4|vsync\.sh";
        e="$e|hh_julie\.sh";
        $KILL -- -$($PS -o pid=,pgid=$LAST_PID,cmd= | $GREP -Pv "$e" |
                    $AWK '{print $1}' | $GREP -Pv "$$") > /dev/null 2>&1;
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
        if echo "$timeToWait_hour" | grep -Pq '^[0-9]$'; then
	    timeToWait_hour="0$timeToWait_hour:";
        else
            timeToWait_hour="$timeToWait_hour:";
        fi
        if echo "$timeToWait_min" | grep -Pq '^[0-9]$'; then
            timeToWait_min="0$timeToWait_min:";
        else
            timeToWait_min="$timeToWait_min:";
        fi
        if echo "$timeToWait_sec" | grep -Pq '^[0-9]$'; then
            timeToWait_sec="0$timeToWait_sec";
        else
            timeToWait_sec="$timeToWait_sec";
        fi
        echo -en "  скрипт запустится через: $timeToWait_hour$timeToWait_min$timeToWait_sec     \r";
        sleep 1;
    done
}

function main(){
    # area=3 - Екатериньбург
    RESUME_ID="$1";
    MSG="$2";
    # $CURL -s -H "$HEADERS_AUTH" "$URL/vacancies?specialization=$spec&area=3" |
    # $JQ -c '.items[] | {id}' | $AWK -F\" '{print $4}' |
    CURL -H "$HEADERS_AUTH" -s -X GET "$URL/resumes/$RESUME_ID/similar_vacancies" |
    $JQ -c '.items[] | {id}' | $AWK -F\" '{print $4}' | $HEAD -n 10 |
    while read vacancy_id; do
        # Если в файле содержится $vacancy_id
        # значит резюме уже отправляли, не будем зря отвлекать людей от работы
        if ! $AWK '{print $2}' "$LOG" | grep -Pq "^$vacancy_id$"; then
            RES_RESPONSE="$($CURL -H "$HEADERS_AUTH" -H "$HEADERS_CONTENT_TYPE" \
                -s -X POST "$URL/negotiations" \
                -F "vacancy_id=$vacancy_id" \
                -F "resume_id=$RESUME_ID" \
                -F "message=$MSG")";
                [[ "a$RES_RESPONSE" != "a" ]] && echo "$RES_RESPONSE" >> $LOG;
            echo "$(date): vacancy_id=$vacancy_id resume_id=$RESUME_ID message=$MSG";
            echo "$(date): $vacancy_id" >> $LOG;
            if echo "$RES_RESPONSE" | grep -Pq "$LIMIT_EXCEEDED"; then
                # Если дневной лимит превышен
                # Ждём 08:00 следующего дня
                # Если дневной лимит превышен
                # Ждём 08:00 следующего дня.
                # Резюме отправлено не будет, но мне это не критично -
                # Одним больше, одним меньше - какая разница если дневной
                # лимит пара сотен =)
                # Тем более оно всё равно будет отправлено со следующего
                # прогона цикла.
                WAIT "08:00 next day";
            elif echo "$RES_RESPONSE" | grep -Pq "$ALREADY_APPLIED"; then
                continue;
            fi
        fi
    done
}

resume_1=(  "4e74d323ff0858e2ff0039ed1f4d6777465745" "$MSG Офисный системный администратор" );
resume_2=(  "9d358b41ff08591f1c0039ed1f476c6d774b39" "$MSG Программист" );
resume_3=(  "332ca78fff0919389b0039ed1f6c714664366a" "$MSG Разнорабочий на стройку" );
resume_4=(  "ee07d3dbff0900273e0039ed1f45344b474959" "$MSG Автослесарь" );
resume_5=(  "d849f7daff09075f990039ed1f707a51596d51" "$MSG Токарь" );
resume_6=(  "bcfadcc6ff090638620039ed1f4e4f7257446c" "$MSG Грузчик" );
resume_7=(  "6d09a93cff0960de0e0039ed1f506b4b584d48" "$MSG Кладовщик, товаровед" );
resume_8=(  "600d4186ff09075e1c0039ed1f396e46614258" "$MSG Слесарь МСР" );
resume_9=(  "dcdd9af5ff094b848b0039ed1f72383069484f" "$MSG Повар-универсал" );
resume_10=( "2d225c89ff09075dc00039ed1f67747945694d" "$MSG Ученик оператора ЧПУ" );
resume_11=( "f10e1a58ff090760db0039ed1f596d35707473" "$MSG Ученик сварщика" );

while true; do
    now="$($DATE +%-H)";
    if [[ "$now" -gt "20" ]]; then
        WAIT "08:00 next day"; # Не беспокоим людей в вечернее время
    elif [[ "$now" -lt "11" ]]; then
        WAIT "08:00"; # Не беспокоим ночью, дождёмся начала рабочего дня (08:00)
    fi
    /my_bin/telegram_send.sh "response_hh.sh: start send resumes" > /dev/null 2>&1;
    main "${resume_1[0]}" "${resume_1[1]}" || FATAL_ERROR="true"; $SLEEP 1m;
    main "${resume_2[0]}" "${resume_2[1]}" || FATAL_ERROR="true"; $SLEEP 1m;
    main "${resume_3[0]}" "${resume_3[1]}" || FATAL_ERROR="true"; $SLEEP 1m;
    main "${resume_4[0]}" "${resume_4[1]}" || FATAL_ERROR="true"; $SLEEP 1m;
    main "${resume_5[0]}" "${resume_5[1]}" || FATAL_ERROR="true"; $SLEEP 1m;
    main "${resume_6[0]}" "${resume_6[1]}" || FATAL_ERROR="true"; $SLEEP 1m;
    main "${resume_7[0]}" "${resume_7[1]}" || FATAL_ERROR="true"; $SLEEP 1m;
    main "${resume_8[0]}" "${resume_8[1]}" || FATAL_ERROR="true"; $SLEEP 1m;
    main "${resume_9[0]}" "${resume_9[1]}" || FATAL_ERROR="true"; $SLEEP 1m;
    main "${resume_10[0]}" "${resume_10[1]}" || FATAL_ERROR="true"; $SLEEP 1m;
    main "${resume_11[0]}" "${resume_11[1]}" || FATAL_ERROR="true"; $SLEEP 1m;
    if [[ -z $FATAL_ERROR ]]; then
        /my_bin/telegram_send.sh "response_hh.sh: resumes successfully sended" > /dev/null 2>&1;
    else
        /my_bin/telegram_send.sh "response_hh.sh: your intervention is needed!" > /dev/null 2>&1;
    fi
done
