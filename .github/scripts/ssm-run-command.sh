#!/bin/bash
# Runs a shell command on an EC2 instance via SSM Run Command and polls it
# to completion. Retries send-command while the SSM agent registers.
# Usage: ssm-run-command.sh <instance-id> <command> <poll-attempts>
set -euo pipefail

instance_id="${1:?Usage: $0 <instance-id> <command> <poll-attempts>}"
command="${2:?Usage: $0 <instance-id> <command> <poll-attempts>}"
poll_attempts="${3:?Usage: $0 <instance-id> <command> <poll-attempts>}"

params=$(jq -n --arg script "$command" '{commands: [$script]}')

command_id=""
for attempt in $(seq 1 12); do
  command_id=$(aws ssm send-command \
    --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --parameters "$params" \
    --query "Command.CommandId" --output text 2>/tmp/ssm_err) && break
  echo "send-command attempt $attempt failed, retrying in 10s:" >&2
  cat /tmp/ssm_err >&2
  sleep 10
done
if [ -z "$command_id" ]; then
  echo "send-command never succeeded" >&2
  exit 1
fi

for i in $(seq 1 "$poll_attempts"); do
  status=$(aws ssm get-command-invocation \
    --command-id "$command_id" --instance-id "$instance_id" \
    --query "Status" --output text 2>/dev/null || echo "Pending")
  case "$status" in
    Success) exit 0 ;;
    Failed|Cancelled|TimedOut) echo "SSM command failed: $status" >&2; exit 1 ;;
  esac
  sleep 10
done
echo "Timed out waiting for SSM command to finish" >&2
exit 1
