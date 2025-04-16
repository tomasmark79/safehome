#!/usr/bin/env bash
# This script creates a snapshot of the specified LVM volume(s)
# and backs up the snapshot using either rsync or tar

# (c) Tomáš Mark 2025

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Re-running with sudo..."
  exec sudo "$0" "$@"
fi

# excluded objects are defined in the file ./excluded-fs-objects.conf
# space characters need to be escaped with a double quote ex. "Don'tbackup"
# no trailing slashes are allowed
# no trailing asterisks are allowed

# example usage:

# rsync vytváří vždy nový adresář pro každou zálohu (uchovává historii záloh)
# rsync_notimestamp přepisuje předchozí zálohu ve stejném adresáři (udržuje pouze nejnovější zálohu)
# nepoužívat konečné lomítko!
# ./lvm-backup.sh rsync_notimestamp lv_home
# ./lvm-backup.sh rsync lv_var

# tar používá RELATIVNÍ CESTY, aby správně fungoval exclude = nepoužívat konečné lomítko!
# ./lvm-backup.sh tar lv_usr_local lv_root lv_var


# Get the directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set -euo pipefail

# Default values
VG_NAME="vg_main"
SNAP_SIZE="10G"
LOG_FILE="/var/log/lvm-backup.log"
EXCLUDED_ITEMS="${SCRIPT_DIR}/excluded-fs-objects.conf"
SSH_PORT=7922
SSH_USER="tomas"
SSH_HOST="192.168.79.11"
REMOTE_BASE_DIR="/volume1/homebackup/bluediamond"

# Read parameters
BACKUP_METHOD=${1:-rsync_notimestamp}  # Default to rsync if no parameter is provided
shift
VOLUMES=("$@")

log() {
  local MESSAGE="$1"
  echo "$(date +"%Y-%m-%d %H:%M:%S") : ${MESSAGE}" | tee -a "${LOG_FILE}" | logger -t lvm-backup
}

cleanup() {
  if mountpoint -q "${MNT_DIR}"; then
    log "Unmounting snapshot ${SNAP_NAME}"
    umount "${MNT_DIR}" || log "Failed to unmount snapshot ${SNAP_NAME}"
  fi

  if lvdisplay "${SNAP_DEV}" &>/dev/null; then
    log "Removing snapshot ${SNAP_NAME}"
    lvremove -y "${SNAP_DEV}" || log "Failed to remove snapshot ${SNAP_NAME}"
  fi

  rmdir "${MNT_DIR}" 2>/dev/null || true
}

trap cleanup EXIT

for VOL in "${VOLUMES[@]}"; do
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  SNAP_NAME="snap_${VOL}_${TIMESTAMP}"
  SNAP_DEV="/dev/${VG_NAME}/${SNAP_NAME}"
  ORIG_DEV="/dev/${VG_NAME}/${VOL}"
  MNT_DIR="/mnt/${SNAP_NAME}"

  log "Creating snapshot for ${VOL}"
  if ! lvcreate -L "${SNAP_SIZE}" -s -n "${SNAP_NAME}" "${ORIG_DEV}"; then
    log "Failed to create snapshot for ${VOL}"
    exit 1
  fi

  log "Mounting snapshot ${SNAP_NAME}"
  mkdir -p "${MNT_DIR}"
  if ! mount "${SNAP_DEV}" "${MNT_DIR}"; then
    log "Failed to mount snapshot ${SNAP_NAME}"
    exit 1
  fi

  if [ "${BACKUP_METHOD}" == "tar" ]; then
    log "Starting tar backup for ${VOL}"
    EXCLUDE_ARGS=$(awk '{gsub(/^\/+/, ""); print "--exclude=./" $0}' "${EXCLUDED_ITEMS}" | xargs)
    echo "EXCLUDE_ARGS: ${EXCLUDE_ARGS}"
    if tar cvpz ${EXCLUDE_ARGS} -C "${MNT_DIR}" . | ssh -i ~/.ssh/id_rsa_backupagent -p ${SSH_PORT} ${SSH_USER}@${SSH_HOST} "cat > ${REMOTE_BASE_DIR}/${VOL}_${TIMESTAMP}.tar.gz"; then
      log "Tar backup completed successfully for ${VOL}"
    else
      log "Tar backup failed for ${VOL}"
    fi
  elif [ "${BACKUP_METHOD}" == "rsync_notimestamp" ]; then
    log "Starting rsync_raw for ${VOL}"
    if rsync -az \
        --exclude-from="${EXCLUDED_ITEMS}" \
        -e "ssh -p ${SSH_PORT}" \
        -v \
        "${MNT_DIR}/" \
        "${SSH_USER}@${SSH_HOST}:${REMOTE_BASE_DIR}/${VOL}/"; then
      log "Rsync_raw backup completed successfully for ${VOL}"
    else
      log "Rsync_raw backup failed for ${VOL}"
    fi
  elif [ "${BACKUP_METHOD}" == "rsync" ]; then
    log "Starting rsync for ${VOL}"
    if rsync -az \
        --exclude-from="${EXCLUDED_ITEMS}" \
        -e "ssh -p ${SSH_PORT}" \
        -v \
        "${MNT_DIR}/" \
        "${SSH_USER}@${SSH_HOST}:${REMOTE_BASE_DIR}/${VOL}_${TIMESTAMP}/"; then
      log "Rsync backup completed successfully for ${VOL}"
    else
      log "Rsync backup failed for ${VOL}"
    fi
  fi

  log "Backup for ${VOL} completed successfully"
  
  cleanup
done

log "All backups completed successfully"