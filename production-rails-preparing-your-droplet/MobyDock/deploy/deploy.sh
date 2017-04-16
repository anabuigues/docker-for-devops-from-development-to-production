#!/bin/bash


APP_ENV="${APP_ENV:-staging}"
SERVER_IP="${SERVER_IP:-192.168.1.99}"
SSH_USER="${SSH_USER:-$(whoami)}"
KEY_USER="${KEY_USER:-$(whoami)}"
DOCKER_VERSION="${DOCKER_VERSION:-1.8.3}"

DOCKER_PULL_IMAGES=("postgres:9.4.5" "redis:2.8.22")
COPY_UNIT_FILES=("iptables-restore" "swap" "postgres" "redis" "mobydock" "nginx")
SSL_CERT_BASE_NAME="productionexample"


function preseed_staging() {
cat << EOF
STAGING SERVER (DIRECT VIRTUAL MACHINE) DIRECTIONS:
  1. Configure a static IP address directly on the VM
     su
     <enter password>
     nano /etc/network/interfaces
     [change the last line to look like this, remember to set the correct
      gateway for your router's IP address if it's not 192.168.1.1]
iface eth0 inet static
  address ${SERVER_IP}
  netmask 255.255.255.0
  gateway 192.168.1.1

  2. Reboot the VM and ensure the Debian CD is mounted

  3. Install sudo
     apt-get update && apt-get install -y -q sudo

  4. Add the user to the sudo group
     adduser ${SSH_USER} sudo

  5. Run the commands in: ${0} --help
     Example:
       ./deploy.sh -a
EOF
}

function preseed_production() {
  echo "Preseeding the production server..."
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
adduser --disabled-password --gecos \"\" ${KEY_USER}
apt-get update && apt-get install -y -q sudo
adduser ${KEY_USER} sudo
  '"
  echo "done!"
}

function configure_sudo () {
  echo "Configuring passwordless sudo..."
  scp "sudo/sudoers" "${SSH_USER}@${SERVER_IP}:/tmp/sudoers"
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo chmod 440 /tmp/sudoers
sudo chown root:root /tmp/sudoers
sudo mv /tmp/sudoers /etc
  '"
  echo "done!"
}

function add_ssh_key() {
  echo "Adding SSH key..."
  cat "$HOME/.ssh/id_rsa.pub" | ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
mkdir /home/${KEY_USER}/.ssh
cat >> /home/${KEY_USER}/.ssh/authorized_keys
    '"
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
chmod 700 /home/${KEY_USER}/.ssh
chmod 640 /home/${KEY_USER}/.ssh/authorized_keys
sudo chown ${KEY_USER}:${KEY_USER} -R /home/${KEY_USER}/.ssh
  '"
  echo "done!"
}

function configure_secure_ssh () {
  echo "Configuring secure SSH..."
  scp "ssh/sshd_config" "${SSH_USER}@${SERVER_IP}:/tmp/sshd_config"
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo chown root:root /tmp/sshd_config
sudo mv /tmp/sshd_config /etc/ssh
sudo systemctl restart ssh
  '"
  echo "done!"
}

function install_docker () {
  echo "Configuring Docker v${1}..."
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo apt-get update
sudo apt-get install -y -q libapparmor1 aufs-tools ca-certificates
wget -O "docker.deb https://apt.dockerproject.org/repo/pool/main/d/docker-engine/docker-engine_${1}-0~jessie_amd64.deb"
sudo dpkg -i docker.deb
rm docker.deb
sudo usermod -aG docker "${KEY_USER}"
  '"
  echo "done!"
}

function docker_pull () {
  echo "Pulling Docker images..."
  for image in "${DOCKER_PULL_IMAGES[@]}"
  do
    ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'docker pull ${image}'"
  done
  echo "done!"
}

function git_init () {
  echo "Initialize git repo and hooks..."
  scp "git/post-receive/mobydock" "${SSH_USER}@${SERVER_IP}:/tmp/mobydock"
  scp "git/post-receive/nginx" "${SSH_USER}@${SERVER_IP}:/tmp/nginx"
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo apt-get update && sudo apt-get install -y -q git
sudo rm -rf /var/git/mobydock.git /var/git/mobydock /var/git/nginx.git /var/git/nginx
sudo mkdir -p /var/git/mobydock.git /var/git/mobydock /var/git/nginx.git /var/git/nginx
sudo git --git-dir=/var/git/mobydock.git --bare init
sudo git --git-dir=/var/git/nginx.git --bare init

sudo mv /tmp/mobydock /var/git/mobydock.git/hooks/post-receive
sudo mv /tmp/nginx /var/git/nginx.git/hooks/post-receive
sudo chmod +x /var/git/mobydock.git/hooks/post-receive /var/git/nginx.git/hooks/post-receive
sudo chown ${KEY_USER}:${KEY_USER} -R /var/git/mobydock.git /var/git/mobydock.git /var/git/mobydock /var/git/nginx.git /var/git/nginx
  '"
  echo "done!"
}

function configure_firewall () {
  echo "Configuring iptables firewall..."
  scp "iptables/rules-save" "${SSH_USER}@${SERVER_IP}:/tmp/rules-save"
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo mkdir -p /var/lib/iptables
sudo mv /tmp/rules-save /var/lib/iptables
sudo chown root:root -R /var/lib/iptables
  '"
  echo "done!"
}

function copy_units () {
  echo "Copying systemd unit files..."
  for unit in "${COPY_UNIT_FILES[@]}"
  do
    scp "units/${unit}.service" "${SSH_USER}@${SERVER_IP}:/tmp/${unit}.service"
    ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo mv /tmp/${unit}.service /etc/systemd/system
sudo chown ${SSH_USER}:${SSH_USER} /etc/systemd/system/${unit}.service
  '"
  done
  echo "done!"
}

function enable_base_units () {
  echo "Enabling base systemd units..."
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo systemctl enable iptables-restore.service
sudo systemctl start iptables-restore.service
sudo systemctl enable swap.service
sudo systemctl start swap.service
sudo systemctl enable postgres.service
sudo systemctl start postgres.service
sudo systemctl enable redis.service
sudo systemctl start redis.service
  '"
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'sudo systemctl restart docker'"
  echo "done!"
}

function copy_env_config_files () {
  echo "Copying environment/config files..."
  scp "${APP_ENV}/.mobydock.env" "${SSH_USER}@${SERVER_IP}:/tmp/.mobydock.env"
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo mkdir -p /home/${KEY_USER}/config
sudo mv /tmp/.mobydock.env /home/${KEY_USER}/config/.mobydock.env
sudo chown ${KEY_USER}:${KEY_USER} -R /home/${KEY_USER}/config
  '"
  echo "done!"
}

function copy_ssl_certs () {
  echo "Copying SSL certificates..."
if [[ "${APP_ENV}" == "staging" ]]; then
  scp "nginx/certs/${SSL_CERT_BASE_NAME}.crt" "${SSH_USER}@${SERVER_IP}:/tmp/${SSL_CERT_BASE_NAME}.crt"
  scp "nginx/certs/${SSL_CERT_BASE_NAME}.key" "${SSH_USER}@${SERVER_IP}:/tmp/${SSL_CERT_BASE_NAME}.key"
  scp "nginx/certs/dhparam.pem" "${SSH_USER}@${SERVER_IP}:/tmp/dhparam.pem"
else
  scp "production/certs/${SSL_CERT_BASE_NAME}.crt" "${SSH_USER}@${SERVER_IP}:/tmp/${SSL_CERT_BASE_NAME}.crt"
  scp "production/certs/${SSL_CERT_BASE_NAME}.key" "${SSH_USER}@${SERVER_IP}:/tmp/${SSL_CERT_BASE_NAME}.key"
  scp "production/certs/dhparam.pem" "${SSH_USER}@${SERVER_IP}:/tmp/dhparam.pem"
fi
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo mv /tmp/${SSL_CERT_BASE_NAME}.crt /etc/ssl/certs/${SSL_CERT_BASE_NAME}.crt
sudo mv /tmp/${SSL_CERT_BASE_NAME}.key /etc/ssl/private/${SSL_CERT_BASE_NAME}.key
sudo mv /tmp/dhparam.pem /etc/ssl/private/dhparam.pem
sudo chown root:root -R /etc/ssl
  '"
  echo "done!"
}

function run_application () {
  echo "Running the application..."
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo systemctl enable mobydock.service nginx.service
sudo systemctl start mobydock.service nginx.service
  '"
  echo "done!"
}

function provision_server () {
  configure_sudo
  echo "---"
  add_ssh_key
  echo "---"
  configure_secure_ssh
  echo "---"
  install_docker ${1}
  echo "---"
  docker_pull
  echo "---"
  git_init
  echo "---"
  configure_firewall
  echo "---"
  copy_units
  echo "---"
  enable_base_units
  echo "---"
  copy_env_config_files
  echo "---"
  copy_ssl_certs
}


function help_menu () {
cat << EOF
Usage: ${0} (-h | -S | -P | -u | -k | -s | -d [docker_ver] | -l | -g | -f | -c | -b | -e | -x | -r | -a [docker_ver])

ENVIRONMENT VARIABLES:
   APP_ENV          Environment that is being deployed to, 'staging' or 'production'
                    Defaulting to ${APP_ENV}

   SERVER_IP        IP address to work on, ie. staging or production
                    Defaulting to ${SERVER_IP}

   SSH_USER         User account to ssh and scp in as
                    Defaulting to ${SSH_USER}

   KEY_USER         User account linked to the SSH key
                    Defaulting to ${KEY_USER}

   DOCKER_VERSION   Docker version to install
                    Defaulting to ${DOCKER_VERSION}

OPTIONS:
   -h|--help                 Show this message
   -S|--preseed-staging      Preseed intructions for the staging server
   -P|--preseed-production   Preseed intructions for the production server
   -u|--sudo                 Configure passwordless sudo
   -k|--ssh-key              Add SSH key
   -s|--ssh                  Configure secure SSH
   -d|--docker               Install Docker
   -l|--docker-pull          Pull necessary Docker images
   -g|--git-init             Install and initialize git
   -f|--firewall             Configure the iptables firewall
   -c|--copy-units           Copy systemd unit files
   -b|--enable-base-units    Enable base systemd unit files
   -e|--copy--environment    Copy app environment/config files
   -x|--ssl-certs            Copy SSL certificates
   -r|--run-app              Run the application
   -a|--all                  Provision everything except preseeding

EXAMPLES:
   Configure passwordless sudo:
        $ deploy -u

   Add SSH key:
        $ deploy -k

   Configure secure SSH:
        $ deploy -s

   Install Docker v${DOCKER_VERSION}:
        $ deploy -d

   Install custom Docker version:
        $ deploy -d 1.8.1

   Pull necessary Docker images:
        $ deploy -l

   Install and initialize git:
        $ deploy -g

   Configure the iptables firewall:
        $ deploy -f

   Copy systemd unit files:
        $ deploy -c

   Enable base systemd unit files:
        $ deploy -b

   Copy app environment/config files:
        $ deploy -e

   Copy SSL certificates:
        $ deploy -x

   Run the application:
        $ deploy -r

   Configure everything together:
        $ deploy -a

   Configure everything together with a custom Docker version:
        $ deploy -a 1.8.1
EOF
}


while [[ $# > 0 ]]
do
case "${1}" in
  -S|--preseed-staging)
  preseed_staging
  shift
  ;;
  -P|--preseed-production)
  preseed_production
  shift
  ;;
  -u|--sudo)
  configure_sudo
  shift
  ;;
  -k|--ssh-key)
  add_ssh_key
  shift
  ;;
  -s|--ssh)
  configure_secure_ssh
  shift
  ;;
  -d|--docker)
  install_docker "${2:-${DOCKER_VERSION}}"
  shift
  ;;
  -l|--docker-pull)
  docker_pull
  shift
  ;;
  -g|--git-init)
  git_init
  shift
  ;;
  -f|--firewall)
  configure_firewall
  shift
  ;;
  -c|--copy-units)
  copy_units
  shift
  ;;
  -b|--enable-base-units)
  enable_base_units
  shift
  ;;
  -e|--copy--environment)
  copy_env_config_files
  shift
  ;;
  -x|--ssl-certs)
  copy_ssl_certs
  shift
  ;;
  -r|--run-app)
  run_application
  shift
  ;;
  -a|--all)
  provision_server "${2:-${DOCKER_VERSION}}"
  shift
  ;;
  -h|--help)
  help_menu
  shift
  ;;
  *)
  echo "${1} is not a valid flag, try running: ${0} --help"
  ;;
esac
shift
done
