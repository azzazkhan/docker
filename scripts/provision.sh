#!/usr/bin/bash

export DEBIAN_FRONTEND=noninteractive

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."

   exit 1
fi


UNAME=$(awk -F= '/^NAME/{print $2}' /etc/os-release | sed 's/\"//g')
if [[ "$UNAME" != "Ubuntu" ]]; then
    echo "This script only supports Ubuntu 20.04, 22.04 and 24.04!"

    exit 1
fi


if [[ -f /root/.provisioned ]]; then
    echo "This server has already been provisioned!"

    exit 1
fi


if [[ ! -f /root/.ssh/authorized_keys ]]; then
    echo "No SSH authorized keys specified for root!"

    exit 1
fi

# Check Permissions Of /root Directory

chown root:root /root
chown -R root:root /root/.ssh

chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys


# Setup custom user

useradd deployer
mkdir -p /home/deployer/.ssh
adduser deployer sudo
passwd -d deployer


# Setup Bash for custom user

chsh -s /bin/bash deployer
cp /root/.profile /home/deployer/.profile
cp /root/.bashrc /home/deployer/.bashrc

# Setup SSH access for custom user

cp /root/.ssh/authorized_keys /home/deployer/.ssh/authorized_keys

chown -R deployer:deployer /home/deployer
chmod -R 755 /home/deployer
chmod 600 /home/deployer/.ssh/authorized_keys

apt_wait () {
    # Run fuser on multiple files once, so that it
    # stops waiting when all files are unlocked

    files="/var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock"
    if [ -f /var/log/unattended-upgrades/unattended-upgrades.log ]; then
        files="$files /var/log/unattended-upgrades/unattended-upgrades.log"
    fi

    while fuser $files >/dev/null 2>&1 ; do
        echo "Waiting for various dpkg or apt locks..."
        sleep 5
    done
}

apt_wait

# Hot fix for IPv6 host resolution error
# @see https://www.reddit.com/r/linuxquestions/comments/ot40dj/comment/h6sy9za/

sed -i "s/#precedence ::ffff:0:0\/96  100/precedence ::ffff:0:0\/96  100/" /etc/gai.conf

# Configure swap memory limit using `round(sqrt(RAM))` to calculate swap size

if [ -f /swapfile ]; then
    echo "Swap exists."
else
    RAM_SIZE=$(free -g | awk '/^Mem:/{print $2}')
    RAM_SIZE=$((RAM_SIZE + 1))

    SWAP_SIZE=$(echo "sqrt($RAM_SIZE)" | bc)
    SWAP_SIZE=$(printf "%.0f" $SWAP_SIZE)

    # Update swap size accordingly
    fallocate -l ${SWAP_SIZE}G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
    echo "vm.swappiness=30" >> /etc/sysctl.conf
    echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
fi

echo deployer > /etc/hostname
sed -i "s/127\.0\.0\.1.*localhost/127.0.0.1	deployer.localdomain deployer localhost/" /etc/hosts
hostname deployer

# Upgrade the base packages

export DEBIAN_FRONTEND=noninteractive

apt_wait

apt-get update
apt_wait

apt-get upgrade -y
apt_wait

apt-get install -y curl apt-transport-https ca-certificates \
    software-properties-common

apt_wait

apt-get update
apt_wait

add-apt-repository universe -y
apt_wait

# Install required packages
apt-get --fix-broken install -y cron curl g++ gcc git gnupg jq net-tools \
    python3 python3-dev python3-venv python3-pip pwgen rsyslog supervisor \
    tar ufw unzip wget whois zip zsh  ca-certificates \
    software-properties-common apt-transport-https

MKPASSWD_INSTALLED=$(type mkpasswd &> /dev/null)
if [ $? -ne 0 ]; then
  echo "Failed to install base dependencies."

  exit 1
fi

apt_wait

# Run cron on system boot

systemctl enable cron

# Set the timezon to UTC

ln -sf /usr/share/zoneinfo/UTC /etc/localtime


# Create SSH key for custom user

ssh-keygen -f /home/deployer/.ssh/id_ed25519 -t ed25519 -N ''

# Replace `root` with proper username in generated SSH key

sed -i "s/root@$HOSTNAME/deployer@$HOSTNAME/" /home/deployer/.ssh/id_ed25519.pub

# Copy source control public keys into known hosts file

ssh-keyscan -H github.com >> /home/deployer/.ssh/known_hosts
ssh-keyscan -H bitbucket.org >> /home/deployer/.ssh/known_hosts
ssh-keyscan -H gitlab.com >> /home/deployer/.ssh/known_hosts

# Setup custom user home directory permissions

chown -R deployer:deployer /home/deployer
chmod -R 755 /home/deployer
chmod 400 /home/deployer/.ssh/id_ed25519
chmod 400 /home/deployer/.ssh/id_ed25519.pub
chmod 600 /home/deployer/.ssh/authorized_keys

# Disable password authentication over SSH

if [ ! -d /etc/ssh/sshd_config.d ]; then mkdir /etc/ssh/sshd_config.d; fi

cat << EOF > /etc/ssh/sshd_config.d/50-custom.conf
# This is a custom file

PubkeyAuthentication yes
PasswordAuthentication no

EOF

# Restart SSH

ssh-keygen -A
service ssh restart

# Configure Git settings

git config --global user.name "Worker"
git config --global user.email "worker@example.com"

# Setup UFW firewall

ufw allow 22
ufw allow 80
ufw allow 443

ufw --force enable

# Remove existing Docker installation

for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done

# Install Docker and Docker Compose plugin

install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install Docker Rollout plugin (https://github.com/wowu/docker-rollout)

mkdir -p /home/deployer/.docker/cli-plugins \
    && curl https://raw.githubusercontent.com/wowu/docker-rollout/master/docker-rollout -o /home/deployer/.docker/cli-plugins/docker-rollout \
    && chmod +x /home/deployer/.docker/cli-plugins/docker-rollout

# Allow local user to access `docker` command without using sudo

sudo usermod -aG docker deployer

# Set permissions of local user's home directory

chown -R deployer:deployer /home/deployer

# Register the Docker service to auto-start on system boot

systemctl enable docker.service && systemctl enable containerd.service

# Register the Supervisor service to auto-start on system boot

systemctl enable supervisor.service && service supervisor start

# Add cron entry for auto removing dangling images

echo "0 0 * * * /usr/bin/docker image prune --all --force" | crontab -u deployer -

# Configure max open file limit for custom user

echo "" >> /etc/security/limits.conf
echo "deployer        soft  nofile  10000" >> /etc/security/limits.conf
echo "deployer        hard  nofile  10000" >> /etc/security/limits.conf
echo "" >> /etc/security/limits.conf

systemctl enable supervisor.service
service supervisor start

systemctl daemon-reload

touch /root/.provisioned
