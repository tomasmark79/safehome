#!/usr/bin/env bash

# (c) Tomáš Mark 2025
# tato verze je pro zálohování složek přímo, nikoliv LVM snapšotů

# example usage:
# ./folder-backup.sh

# excluded objects are defined in the file ./excluded-fs-objects.conf
# the file should contain a list of directories to exclude from the backup
# each directory should be on a separate line
# no trailing slashes are allowed
# no trailing asterisks are allowed


# Get the directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
SOURCE_DIR="/home/"
REMOTE_USER="tomas"
REMOTE_HOST="192.168.79.11"
REMOTE_PORT=7922
REMOTE_DIR="/volume1/homebackup/rebian/home-tomas/"

EXCLUDED_ITEMS="${SCRIPT_DIR}/excluded-fs-objects.conf"
LOG_FILE="/var/log/home-backup.log"

log() {
  local MESSAGE="$1"
  echo "$(date +"%Y-%m-%d %H:%M:%S") : ${MESSAGE}" | sudo tee -a "${LOG_FILE}"
}

backup() {
  log "Starting backup from ${SOURCE_DIR} to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"
    log "StartTime: $(date)"
  if rsync -az --exclude-from="${EXCLUDED_ITEMS}" -e "ssh -p ${REMOTE_PORT}" "${SOURCE_DIR}/" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"; then
    log "Backup completed successfully. EndTime: $(date)"
  else
    log "Backup failed. EndTime: $(date)"
    exit 1
  fi
}

backup