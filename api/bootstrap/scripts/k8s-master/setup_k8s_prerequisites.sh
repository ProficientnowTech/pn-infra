#!/bin/bash
# Kubernetes Prerequisites Setup Script
# Sets up directories, permissions, and basic configuration for Kubernetes

set -euo pipefail

echo "Setting up Kubernetes prerequisites..."

# Create required directories
DIRECTORIES=(
	"/etc/kubernetes/manifests"
	"/etc/kubernetes/pki"
	"/var/lib/etcd"
	"/opt/cni/bin"
	"/etc/cni/net.d"
	"/var/lib/kubelet"
	"/var/lib/kubelet/pki"
)

for dir in "${DIRECTORIES[@]}"; do
	echo "Creating directory: $dir"
	mkdir -p "$dir"

	# Set appropriate permissions based on directory
	case "$dir" in
		"/var/lib/etcd")
			chmod 700 "$dir"
			chown root:root "$dir"
			;;
		"/etc/kubernetes/pki" | "/var/lib/kubelet/pki")
			chmod 755 "$dir"
			chown root:root "$dir"
			;;
		*)
			chmod 755 "$dir"
			chown root:root "$dir"
			;;
	esac
done

# Create k8s-admin user if not exists
if ! id "k8s-admin" &> /dev/null; then
	echo "Creating k8s-admin user..."
	useradd -m -s /bin/bash -G sudo,docker k8s-admin

	# Configure sudo access
	echo "k8s-admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/k8s-admin
	chmod 440 /etc/sudoers.d/k8s-admin
fi

# Configure containerd for Kubernetes
if [ -f "/etc/containerd/config.toml" ]; then
	echo "Configuring containerd for Kubernetes..."

	# Backup original config
	cp /etc/containerd/config.toml /etc/containerd/config.toml.backup

	# Configure systemd cgroup driver
	containerd config default > /etc/containerd/config.toml
	sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

	# Restart containerd
	systemctl restart containerd
	systemctl enable containerd
fi

echo "Kubernetes prerequisites setup completed successfully"
