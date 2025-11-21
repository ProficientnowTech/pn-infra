#!/bin/bash
# rook-disk-reset.sh
# Standalone Rook-Ceph disk and directory cleanup (no Kubernetes required)
# Run this script directly on each node or via SSH

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DEVICE="${1:-/dev/sdb}" # Pass device as argument or use default
FORCE="${2:-false}"     # Pass 'force' as second argument to skip confirmation

echo -e "${RED}☢️  ROOK-CEPH DISK CLEANUP${NC}"
echo -e "${RED}============================${NC}"
echo -e "${YELLOW}This will:${NC}"
echo -e "${YELLOW}  1. Stop all Ceph processes${NC}"
echo -e "${YELLOW}  2. Remove all LVM volumes${NC}"
echo -e "${YELLOW}  3. Wipe disk: $DEVICE${NC}"
echo -e "${YELLOW}  4. Delete /var/lib/rook and /var/lib/ceph${NC}"
echo -e "${RED}  WARNING: ALL DATA ON $DEVICE WILL BE LOST!${NC}"
echo ""

if [ "$FORCE" != "force" ]; then
	echo -e "${YELLOW}Type 'WIPE' to confirm:${NC}"
	read -r confirmation

	if [ "$confirmation" != "WIPE" ]; then
		echo "Aborted."
		exit 0
	fi
fi

echo ""
echo -e "${GREEN}Starting cleanup on $(hostname)...${NC}"

# ============================================================================
# STEP 1: Stop all Ceph processes
# ============================================================================
echo ""
echo -e "${BLUE}[1/7] Stopping Ceph processes...${NC}"

# Stop systemd Ceph services
systemctl stop ceph\* 2>/dev/null || true
systemctl stop rook\* 2>/dev/null || true

# Kill any remaining Ceph processes
pkill -9 ceph-mon 2>/dev/null || true
pkill -9 ceph-osd 2>/dev/null || true
pkill -9 ceph-mgr 2>/dev/null || true
pkill -9 ceph-mds 2>/dev/null || true
pkill -9 radosgw 2>/dev/null || true
pkill -9 ceph 2>/dev/null || true

echo "✓ Ceph processes stopped"

# ============================================================================
# STEP 2: Unmount all Ceph filesystems
# ============================================================================
echo ""
echo -e "${BLUE}[2/7] Unmounting Ceph filesystems...${NC}"

# Unmount specific directories
umount -f /var/lib/rook 2>/dev/null || true
umount -f /var/lib/ceph 2>/dev/null || true
umount -f /var/lib/kubelet/plugins 2>/dev/null || true
umount -f /var/lib/kubelet/plugins_registry 2>/dev/null || true

# Find and unmount all Ceph-related mounts
mount | grep -E 'ceph|rook' | awk '{print $3}' | while read mountpoint; do
	echo "Unmounting: $mountpoint"
	umount -f "$mountpoint" 2>/dev/null || true
done

# Force unmount anything on the target device
mount | grep "$DEVICE" | awk '{print $3}' | while read mountpoint; do
	echo "Force unmounting: $mountpoint"
	umount -f "$mountpoint" 2>/dev/null || true
done

echo "✓ Filesystems unmounted"

# ============================================================================
# STEP 3: Remove LVM volumes
# ============================================================================
echo ""
echo -e "${BLUE}[3/7] Removing LVM volumes...${NC}"

# Deactivate all volume groups
vgchange -an 2>/dev/null || true

# Remove Ceph volume groups
vgs --noheadings -o vg_name 2>/dev/null | grep -iE 'ceph|rook' | while read vg; do
	echo "Removing VG: $vg"
	vgremove -f "$vg" 2>/dev/null || true
done

# Remove all volume groups on the target device
vgs --noheadings -o vg_name,pv_name 2>/dev/null | grep "$DEVICE" | awk '{print $1}' | while read vg; do
	echo "Removing VG: $vg (on $DEVICE)"
	vgremove -f "$vg" 2>/dev/null || true
done

# Remove physical volumes on the target device
pvs --noheadings -o pv_name 2>/dev/null | grep "$DEVICE" | while read pv; do
	echo "Removing PV: $pv"
	pvremove -ff "$pv" 2>/dev/null || true
done

echo "✓ LVM volumes removed"

# ============================================================================
# STEP 4: Remove device mapper devices
# ============================================================================
echo ""
echo -e "${BLUE}[4/7] Removing device mapper devices...${NC}"

# Remove Ceph device mapper devices
dmsetup ls --target crypt 2>/dev/null | grep -iE 'ceph|rook' | awk '{print $1}' | while read dm; do
	echo "Removing DM: $dm"
	dmsetup remove --force "$dm" 2>/dev/null || true
done

# Remove all device mapper devices related to the target device
DEVICE_NAME="${DEVICE##*/}"
dmsetup ls 2>/dev/null | grep "$DEVICE_NAME" | awk '{print $1}' | while read dm; do
	echo "Removing DM: $dm"
	dmsetup remove --force "$dm" 2>/dev/null || true
done

echo "✓ Device mapper devices removed"

# ============================================================================
# STEP 5: Wipe the disk
# ============================================================================
echo ""
echo -e "${BLUE}[5/7] Wiping disk: $DEVICE${NC}"

# Check if device exists
if [ ! -b "$DEVICE" ]; then
	echo -e "${RED}ERROR: Device $DEVICE does not exist!${NC}"
	echo "Available block devices:"
	lsblk
	exit 1
fi

# Zap all partitions using sgdisk
echo "Zapping GPT/MBR partition tables..."
sgdisk --zap-all "$DEVICE" 2>/dev/null || true

# Zero out the beginning of the disk (first 100MB)
echo "Zeroing first 100MB of disk..."
dd if=/dev/zero of="$DEVICE" bs=1M count=100 oflag=direct,dsync 2>/dev/null || true

# Zero out the end of the disk (last 100MB)
echo "Zeroing last 100MB of disk..."
DISK_SIZE=$(blockdev --getsz "$DEVICE")
END_OFFSET=$((DISK_SIZE - 204800)) # 100MB in 512-byte sectors
dd if=/dev/zero of="$DEVICE" bs=512 count=204800 seek=$END_OFFSET oflag=direct,dsync 2>/dev/null || true

# Wipe all filesystem signatures
echo "Wiping filesystem signatures..."
wipefs --all --force "$DEVICE" 2>/dev/null || true

# For each partition on the device
for partition in "${DEVICE}"*; do
	if [ "$partition" != "$DEVICE" ] && [ -b "$partition" ]; then
		echo "Wiping partition: $partition"
		wipefs --all --force "$partition" 2>/dev/null || true
	fi
done

# Inform kernel of partition table changes
echo "Re-reading partition table..."
partprobe "$DEVICE" 2>/dev/null || true
blockdev --rereadpt "$DEVICE" 2>/dev/null || true

# Final verification
sleep 2
echo ""
echo "Disk status after wipe:"
lsblk "$DEVICE"
blkid "$DEVICE" 2>/dev/null || echo "No filesystem found (clean)"

echo "✓ Disk wiped successfully"

# ============================================================================
# STEP 6: Clean up directories
# ============================================================================
echo ""
echo -e "${BLUE}[6/7] Cleaning up directories...${NC}"

# Remove Rook directories
if [ -d /var/lib/rook ]; then
	echo "Removing /var/lib/rook..."
	rm -rf /var/lib/rook
	echo "✓ Removed /var/lib/rook"
fi

# Remove Ceph directories
if [ -d /var/lib/ceph ]; then
	echo "Removing /var/lib/ceph..."
	rm -rf /var/lib/ceph
	echo "✓ Removed /var/lib/ceph"
fi

# Remove Ceph configuration
if [ -d /etc/ceph ]; then
	echo "Removing /etc/ceph..."
	rm -rf /etc/ceph
	echo "✓ Removed /etc/ceph"
fi

# Remove systemd units
echo "Removing Ceph systemd units..."
rm -f /etc/systemd/system/ceph*.service 2>/dev/null || true
rm -f /etc/systemd/system/rook*.service 2>/dev/null || true
systemctl daemon-reload

# Clean up any Ceph-related temp files
rm -rf /tmp/ceph-* 2>/dev/null || true
rm -rf /tmp/rook-* 2>/dev/null || true

echo "✓ Directories cleaned"

# ============================================================================
# STEP 7: Final verification
# ============================================================================
echo ""
echo -e "${BLUE}[7/7] Final verification...${NC}"

echo ""
echo "=== System Status ==="
echo ""
echo "Running processes:"
ps aux | grep -iE 'ceph|rook' | grep -v grep || echo "  ✓ No Ceph/Rook processes running"

echo ""
echo "Mounted filesystems:"
mount | grep -iE 'ceph|rook' || echo "  ✓ No Ceph/Rook mounts"

echo ""
echo "LVM status:"
pvs 2>/dev/null | grep -iE 'ceph|rook' || echo "  ✓ No Ceph/Rook PVs"
vgs 2>/dev/null | grep -iE 'ceph|rook' || echo "  ✓ No Ceph/Rook VGs"

echo ""
echo "Device mapper:"
dmsetup ls 2>/dev/null | grep -iE 'ceph|rook' || echo "  ✓ No Ceph/Rook DM devices"

echo ""
echo "Disk status ($DEVICE):"
lsblk "$DEVICE"

# ============================================================================
# Completion
# ============================================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Cleanup complete on $(hostname)!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}Device $DEVICE is clean and ready for reuse.${NC}"
echo ""
