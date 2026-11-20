#!/bin/bash
set -euo pipefail

dnf install -y docker
systemctl enable --now docker
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-aarch64" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Recent docker-compose needs buildx >= 0.17 to build images, and the AL2023
# docker package doesn't ship it. Pinned so a new release can't break boot.
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/buildx/releases/download/v0.19.3/buildx-v0.19.3.linux-arm64" \
  -o /usr/local/lib/docker/cli-plugins/docker-buildx
chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

mkdir -p /opt/jenkins/secrets /opt/jenkins/exporter-config /opt/jenkins/app/jcasc
chmod 755 /opt/jenkins/secrets

aws ssm get-parameter --with-decryption --region "${aws_region}" \
  --name "${ssh_key_param_name}" --query Parameter.Value --output text \
  > /opt/jenkins/secrets/linode_ssh_key
chmod 644 /opt/jenkins/secrets/linode_ssh_key

aws ssm get-parameter --with-decryption --region "${aws_region}" \
  --name "${admin_password_param}" --query Parameter.Value --output text \
  > /opt/jenkins/secrets/admin_password
chmod 644 /opt/jenkins/secrets/admin_password

exporter_hash=$(aws ssm get-parameter --with-decryption --region "${aws_region}" \
  --name "${exporter_hash_param}" --query Parameter.Value --output text)
cat > /opt/jenkins/exporter-config/web-config.yml <<EOF
basic_auth_users:
  metrics: $${exporter_hash}
EOF

chmod 644 /opt/jenkins/exporter-config/web-config.yml

cat > /opt/jenkins/app/jcasc/jenkins.yaml <<'JCASC_EOF'
${jcasc_content}
JCASC_EOF

cat > /opt/jenkins/app/docker-compose.yml <<'COMPOSE_EOF'
${docker_compose_content}
COMPOSE_EOF

cat > /opt/jenkins/app/Dockerfile <<'DOCKERFILE_EOF'
${dockerfile_content}
DOCKERFILE_EOF

echo "LINODE_HOST=${linode_host}" > /opt/jenkins/app/.env
echo "DOCKER_GID=$(getent group docker | cut -d: -f3)" >> /opt/jenkins/app/.env

cd /opt/jenkins/app
docker-compose up -d --build
