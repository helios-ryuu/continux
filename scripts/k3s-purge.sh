#!/bin/bash

# Script: k3s-purge.sh
# Purpose: Clear all K3s components, configs, and network interfaces

echo "Stopping K3s services..."
sudo systemctl stop k3s k3s-agent 2>/dev/null || true

echo "Running official killall and uninstall scripts..."
[ -f /usr/local/bin/k3s-killall.sh ] && sudo /usr/local/bin/k3s-killall.sh 2>/dev/null
[ -f /usr/local/bin/k3s-uninstall.sh ] && sudo /usr/local/bin/k3s-uninstall.sh 2>/dev/null
[ -f /usr/local/bin/k3s-agent-uninstall.sh ] && sudo /usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null

echo "Removing directories and configurations..."
sudo rm -rf /etc/rancher /var/lib/rancher /var/lib/kubelet /run/k3s /var/lib/k3s
sudo rm -rf /etc/cni /opt/cni /var/lib/cni
sudo rm -rf /var/log/pods /var/log/containers

echo "Cleaning up systemd and binaries..."
sudo rm -f /etc/systemd/system/k3s*
sudo systemctl daemon-reload
sudo rm -f /usr/local/bin/k3s /usr/local/bin/kubectl /usr/local/bin/crictl /usr/local/bin/ctr

echo "Cleaning up network interfaces..."
sudo ip link delete cni0 2>/dev/null || true
sudo ip link delete flannel.1 2>/dev/null || true
sudo rm -rf /var/run/netns/cni-*

echo "Verification:"
which k3s kubectl > /dev/null || echo "- Binaries: Cleared"
ps aux | grep -E "k3s|containerd" | grep -v grep > /dev/null || echo "- Processes: Cleared"

echo "K3s has been fully removed."