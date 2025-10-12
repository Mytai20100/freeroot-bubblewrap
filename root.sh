#!/usr/bin/env bash
# Ubuntu Server 22.04 in Bubblewrap (PRoot-style)
#By mytai =)) 
#Main idea (https://github.com/foxytouxxx/freeroot)
#Bubblewrap(https://github.com/containers/bubblewrap)
#Power by Phoai(my model AI =)) ) ,mybrain
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
  ARCH_ALT=amd64
elif [ "$ARCH" = "aarch64" ]; then
  ARCH_ALT=arm64
else
  printf "Unsupported CPU architecture: ${ARCH}\n"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BWRAP_BIN="$SCRIPT_DIR/bwrap-${ARCH_ALT}"
BWRAP_URL="https://github.com/Mytai20100/freeroot-bubblewrap/raw/main/bwrap-${ARCH_ALT}"
WORK_DIR="$SCRIPT_DIR/work"
ROOTFS_DIR="$WORK_DIR/rootfs"
UBUNTU_TAR="ubuntu-22.04-server-cloudimg-${ARCH_ALT}-root.tar.xz"
UBUNTU_URL="https://cloud-images.ubuntu.com/releases/22.04/release/$UBUNTU_TAR"

CPU_NAME=$(cat /proc/cpuinfo | grep "model name" | head -n1 | cut -d':' -f2 | xargs | sed 's/ /-/g' | sed 's/[^a-zA-Z0-9-]//g' | tr '[:upper:]' '[:lower:]')
HOSTNAME="${CPU_NAME:-unknown-cpu}"
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
CURRENT_USER=$(id -un)

echo -e "${GREEN}=== Starting Ubuntu Server 22.04 ===${NC}"
echo -e "${YELLOW}Architecture: ${ARCH} (${ARCH_ALT})${NC}"
echo -e "${YELLOW}Bubblewrap: bwrap-${ARCH_ALT}${NC}"

if [ ! -f "$BWRAP_BIN" ]; then
    echo -e "${GREEN}Downloading bwrap-${ARCH_ALT} from GitHub...${NC}"
    if command -v wget &> /dev/null; then
        wget -q --show-progress -O "$BWRAP_BIN" "$BWRAP_URL" || {
            echo -e "${RED}Failed to download bwrap binary!${NC}"
            exit 1
        }
    elif command -v curl &> /dev/null; then
        curl -# -L -o "$BWRAP_BIN" "$BWRAP_URL" || {
            echo -e "${RED}Failed to download bwrap binary!${NC}"
            exit 1
        }
    else
        echo -e "${RED}Neither wget nor curl found! Please install one.${NC}"
        exit 1
    fi
    chmod +x "$BWRAP_BIN"
    echo -e "${GREEN}Downloaded bwrap-${ARCH_ALT} successfully!${NC}"
fi

if [ ! -x "$BWRAP_BIN" ]; then
    echo -e "${RED}bwrap binary not found at: $BWRAP_BIN${NC}"
    exit 1
fi

mkdir -p "$WORK_DIR"

if [ ! -d "$ROOTFS_DIR" ] || [ -z "$(ls -A $ROOTFS_DIR 2>/dev/null)" ]; then
    echo -e "${GREEN}Downloading Ubuntu Server 22.04...${NC}"
    
    cd "$WORK_DIR"
    
    if [ ! -f "$UBUNTU_TAR" ]; then
        wget -q --show-progress "$UBUNTU_URL" || curl -# -L -o "$UBUNTU_TAR" "$UBUNTU_URL" || {
            echo -e "${RED}Failed to download Ubuntu image!${NC}"
            exit 1
        }
    fi
    echo -e "${GREEN}Extracting Ubuntu Server rootfs...${NC}"
    mkdir -p "$ROOTFS_DIR"
    tar -xf "$UBUNTU_TAR" -C "$ROOTFS_DIR" 2>&1 | grep -v "Cannot mknod" | grep -v "tar:" || true
    cd "$SCRIPT_DIR"
fi

mkdir -p "$ROOTFS_DIR"/{proc,sys,dev,tmp,run,root}
mkdir -p "$ROOTFS_DIR/var/lib/"{dpkg,apt/lists/partial}
mkdir -p "$ROOTFS_DIR/var/cache/apt/archives/partial"
mkdir -p "$ROOTFS_DIR/var/log/apt"
mkdir -p "$ROOTFS_DIR/etc/apt/apt.conf.d"
touch "$ROOTFS_DIR/var/lib/dpkg/status"
cat > "$ROOTFS_DIR/etc/apt/apt.conf.d/00sandbox" <<'EOF'
APT::Sandbox::User "root";
EOF
cat > "$ROOTFS_DIR/etc/apt/apt.conf.d/99insecure" <<'EOF'
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
APT::Get::AllowUnauthenticated "true";
EOF

rm -f "$ROOTFS_DIR/etc/resolv.conf"
if [ -f /etc/resolv.conf ]; then
    cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"
else
    cat > "$ROOTFS_DIR/etc/resolv.conf" <<'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
fi

echo "$HOSTNAME" > "$ROOTFS_DIR/etc/hostname"
cat > "$ROOTFS_DIR/etc/hosts" <<EOF
127.0.0.1   localhost
127.0.1.1   $HOSTNAME
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

cat > "$ROOTFS_DIR/etc/passwd" <<EOF
root:x:0:0:root:/root:/bin/bash
_apt:x:100:65534:APT Sandbox:/nonexistent:/usr/sbin/nologin
ubuntu:x:1000:1000:Ubuntu:/home/ubuntu:/bin/bash
EOF
cat > "$ROOTFS_DIR/etc/group" <<EOF
root:x:0:
nogroup:x:65534:
ubuntu:x:1000:
EOF
cat > "$ROOTFS_DIR/etc/shadow" <<'EOF'
root:*:19000:0:99999:7:::
_apt:*:19000:0:99999:7:::
ubuntu:*:19000:0:99999:7:::
EOF

# Set permissions
chmod 644 "$ROOTFS_DIR/etc/passwd" "$ROOTFS_DIR/etc/group"
chmod 640 "$ROOTFS_DIR/etc/shadow" || true
chmod 755 "$ROOTFS_DIR/var/lib/apt/lists" 2>/dev/null || true
chmod 755 "$ROOTFS_DIR/var/cache/apt/archives" 2>/dev/null || true
chmod 1777 "$ROOTFS_DIR/tmp" 2>/dev/null || true

mkdir -p "$ROOTFS_DIR/etc/update-motd.d"
cat > "$ROOTFS_DIR/etc/motd" <<'EOF'
Welcome to Ubuntu 22.04.3 LTS (GNU/Linux 5.15.0-1023-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/advantage

EOF

# Create system info script
cat > "$ROOTFS_DIR/usr/local/bin/show-system-info" <<'EOFSCRIPT'
#!/bin/bash

# System information script - mimics Ubuntu Server style
get_load_average() {
    cat /proc/loadavg | awk '{print $1", "$2", "$3}'
}

get_memory_info() {
    free -m | awk 'NR==2{printf "%dMB / %dMB", $3, $2}'
}

get_swap_info() {
    free -m | awk 'NR==3{if ($2 > 0) printf "%dMB / %dMB", $3, $2; else print "0MB"}'
}

get_disk_usage() {
    df -h / | awk 'NR==2{print $3" / "$2}'
}

get_disk_percent() {
    df -h / | awk 'NR==2{print $5}'
}

get_processes() {
    ps aux | wc -l
}

get_users() {
    who | wc -l
}

get_ipv4() {
    hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A"
}

# Print system info in Ubuntu style
echo ""
echo "System information as of $(date)"
echo ""
printf "  System load:  %-25s   Processes:             %s\n" "$(get_load_average)" "$(get_processes)"
printf "  Usage of /:   %-15s %6s   Users logged in:       %s\n" "$(get_disk_usage)" "$(get_disk_percent)" "$(get_users)"
printf "  Memory usage: %-25s   IPv4 address for eth0: %s\n" "$(get_memory_info)" "$(get_ipv4)"
printf "  Swap usage:   %-25s\n" "$(get_swap_info)"
echo ""
EOFSCRIPT

chmod +x "$ROOTFS_DIR/usr/local/bin/show-system-info"
rm -f "$ROOTFS_DIR/root/.hushlogin"
rm -f "$ROOTFS_DIR/home/ubuntu/.hushlogin"

cat > "$ROOTFS_DIR/etc/profile.d/motd.sh" <<'EOF'
#!/bin/bash
if [ -n "$PS1" ] && [ -f /etc/motd ]; then
    cat /etc/motd
    # Display dynamic system info
    if [ -x /usr/local/bin/show-system-info ]; then
        /usr/local/bin/show-system-info
    fi
fi
EOF
chmod +x "$ROOTFS_DIR/etc/profile.d/motd.sh"

cat > "$ROOTFS_DIR/root/.bashrc" <<'EOF'
# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command
shopt -s checkwinsize

# enable color support
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Prompt
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
EOF

mkdir -p "$ROOTFS_DIR/home/ubuntu"
cat > "$ROOTFS_DIR/home/ubuntu/.bashrc" <<'EOF'
# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s checkwinsize

if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
EOF
echo -e "${GREEN}Starting container...${NC}"
echo ""
exec "$BWRAP_BIN" \
    --bind "$ROOTFS_DIR" / \
    --proc /proc \
    --dev /dev \
    --tmpfs /tmp \
    --tmpfs /run \
    --ro-bind /sys /sys \
    --hostname "$HOSTNAME" \
    --unshare-pid \
    --unshare-ipc \
    --unshare-uts \
    --die-with-parent \
    --uid 0 \
    --gid 0 \
    --setenv HOME /root \
    --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    --setenv USER root \
    --setenv LOGNAME root \
    --setenv SHELL /bin/bash \
    --setenv TERM xterm-256color \
    --setenv DEBIAN_FRONTEND noninteractive \
    --chdir /root \
    /bin/bash -l
