#!/bin/bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_FILE="$BASE_DIR/tasks.txt"
LOG_FILE="$BASE_DIR/logs/reminder.log"
CRON_FILE="$BASE_DIR/cron/reminder-cron.sh"

mkdir -p "$BASE_DIR/logs" "$BASE_DIR/cron"
touch "$TASK_FILE" "$LOG_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

usage() {
    cat <<EOF
Linux Reminder & Task Scheduler

Usage:
  ./reminder.sh add "Task name" "HH:MM" [daily|weekly|once]
  ./reminder.sh list
  ./reminder.sh remove ID
  ./reminder.sh check
  ./reminder.sh start
  ./reminder.sh install-cron
  ./reminder.sh uninstall-cron
  ./reminder.sh logs
  ./reminder.sh help

Examples:
  ./reminder.sh add "Study Signals" "20:00" daily
  ./reminder.sh add "Submit assignment" "22:00" once
  ./reminder.sh list
  ./reminder.sh remove 2
  ./reminder.sh check
  ./reminder.sh install-cron
EOF
}

valid_time() {
    [[ "$1" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]
}

valid_type() {
    [[ "$1" == "daily" || "$1" == "weekly" || "$1" == "once" ]]
}

next_id() {
    awk -F'|' 'BEGIN{max=0} $1 ~ /^[0-9]+$/ && $1>max {max=$1} END{print max+1}' "$TASK_FILE"
}

add_task() {
    local task="$1"
    local time="$2"
    local type="${3:-once}"

    if [[ -z "$task" || -z "$time" ]]; then
        echo "Error: Task and time are required."
        exit 1
    fi

    if ! valid_time "$time"; then
        echo "Error: Time must use HH:MM format, e.g. 20:30."
        exit 1
    fi

    if ! valid_type "$type"; then
        echo "Error: Type must be daily, weekly, or once."
        exit 1
    fi

    local id
    id=$(next_id)
    echo "$id|$task|$time|$type|active|$(date '+%Y-%m-%d')" >> "$TASK_FILE"
    log "ADDED id=$id task=\"$task\" time=$time type=$type"
    echo "Task added successfully. ID: $id"
}

list_tasks() {
    echo
    echo "========== TASKS =========="
    if [[ ! -s "$TASK_FILE" ]]; then
        echo "No tasks found."
        return
    fi

    printf "%-4s %-24s %-8s %-9s %-8s\n" "ID" "TASK" "TIME" "TYPE" "STATUS"
    echo "---------------------------------------------------------------"
    awk -F'|' '$5=="active" {printf "%-4s %-24s %-8s %-9s %-8s\n",$1,$2,$3,$4,$5}' "$TASK_FILE"
    echo
}

remove_task() {
    local id="$1"

    if ! [[ "$id" =~ ^[0-9]+$ ]]; then
        echo "Error: ID must be a number."
        exit 1
    fi

    if ! awk -F'|' -v id="$id" '$1==id && $5=="active" {found=1} END{exit !found}' "$TASK_FILE"; then
        echo "Error: Active task ID $id not found."
        exit 1
    fi

    awk -F'|' -v id="$id" 'BEGIN{OFS="|"} $1==id {$5="deleted"} {print}' "$TASK_FILE" > "$TASK_FILE.tmp"
    mv "$TASK_FILE.tmp" "$TASK_FILE"
    log "REMOVED id=$id"
    echo "Task $id removed."
}

notify() {
    local message="$1"
    echo
    echo "🔔 REMINDER: $message"
    echo
    log "REMINDER: $message"

    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Linux Reminder" "$message"
    fi
}

check_tasks() {
    local now day today
    now=$(date '+%H:%M')
    day=$(date '+%u')
    today=$(date '+%Y-%m-%d')

    local found=0

    while IFS='|' read -r id task time type status created; do
        [[ "$status" == "active" ]] || continue

        if [[ "$time" != "$now" ]]; then
            continue
        fi

        if [[ "$type" == "daily" ]]; then
            notify "$task"
            found=1

        elif [[ "$type" == "weekly" ]]; then
            # Weekly tasks run on the weekday they were created.
            created_day=$(date -d "$created" '+%u' 2>/dev/null)
            if [[ "$created_day" == "$day" ]]; then
                notify "$task"
                found=1
            fi

        elif [[ "$type" == "once" ]]; then
            if [[ "$created" == "$today" ]]; then
                notify "$task"
                awk -F'|' -v id="$id" 'BEGIN{OFS="|"} $1==id {$5="completed"} {print}' "$TASK_FILE" > "$TASK_FILE.tmp"
                mv "$TASK_FILE.tmp" "$TASK_FILE"
                found=1
            fi
        fi
    done < "$TASK_FILE"

    [[ "$found" -eq 1 ]] || echo "No reminders due at $now."
}

start_scheduler() {
    echo "Reminder scheduler started."
    echo "Checking every 30 seconds. Press Ctrl+C to stop."
    log "SCHEDULER STARTED"

    while true; do
        check_tasks >/dev/null
        sleep 30
    done
}

install_cron() {
    local cron_line="* * * * * $CRON_FILE"
    mkdir -p "$(dirname "$CRON_FILE")"

    cat > "$CRON_FILE" <<EOF
#!/bin/bash
"$BASE_DIR/reminder.sh" check
EOF
    chmod +x "$CRON_FILE"

    (crontab -l 2>/dev/null | grep -vF "$CRON_FILE"; echo "$cron_line") | crontab -
    echo "Cron installed. The scheduler will check every minute."
    log "CRON INSTALLED"
}

uninstall_cron() {
    (crontab -l 2>/dev/null | grep -vF "$CRON_FILE") | crontab -
    rm -f "$CRON_FILE"
    echo "Cron entry removed."
    log "CRON UNINSTALLED"
}

show_logs() {
    echo "========== LOG =========="
    tail -n 30 "$LOG_FILE"
}

case "${1:-help}" in
    add)
        add_task "$2" "$3" "$4"
        ;;
    list)
        list_tasks
        ;;
    remove)
        remove_task "$2"
        ;;
    check)
        check_tasks
        ;;
    start)
        start_scheduler
        ;;
    install-cron)
        install_cron
        ;;
    uninstall-cron)
        uninstall_cron
        ;;
    logs)
        show_logs
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
