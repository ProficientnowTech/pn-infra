FROM alpine:3.20

ARG KUBESPRAY_VERSION=2.28.1
ARG KUBECTL_VERSION=1.31.4
ARG HELM_VERSION=3.15.4

ENV PIP_BREAK_SYSTEM_PACKAGES=1

# Base packages + build deps for python wheels + Kubespray checkout
RUN set -eux; \
    apk add --no-cache \
      bash curl tar openssh-client sshpass git python3 py3-pip ca-certificates jq rsync openssl; \
    apk add --no-cache --virtual .build-deps \
      build-base python3-dev libffi-dev openssl-dev; \
    python3 -m pip install --no-cache-dir --break-system-packages \
      ansible==10.7.0; \
    mkdir -p /opt && \
    curl -fsSL "https://github.com/kubernetes-sigs/kubespray/archive/refs/tags/v${KUBESPRAY_VERSION}.tar.gz" \
      -o /tmp/kubespray.tar.gz && \
    tar -xzf /tmp/kubespray.tar.gz -C /opt && \
    mv /opt/kubespray-${KUBESPRAY_VERSION} /opt/kubespray && \
    python3 -m pip install --no-cache-dir --break-system-packages \
      -r /opt/kubespray/requirements.txt; \
    ln -s /opt/kubespray /kubespray; \
    apk del .build-deps; \
    rm -rf /var/cache/apk/* /root/.cache /tmp/kubespray.tar.gz

# kubectl for validation
RUN set -eux; \
    curl -fsSLO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl"; \
    install -m 0755 kubectl /usr/local/bin/kubectl; \
    rm kubectl

# helm for addons
RUN set -eux; \
    curl -fsSLO "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz"; \
    tar -xzf "helm-v${HELM_VERSION}-linux-amd64.tar.gz" -C /tmp; \
    install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm; \
    rm -rf /tmp/linux-amd64 "helm-v${HELM_VERSION}-linux-amd64.tar.gz"

ENV ANSIBLE_HOST_KEY_CHECKING=False \
    PYTHONUNBUFFERED=1 \
    KUBESPRAY_HOME=/opt/kubespray

WORKDIR /workspace

CMD ["/bin/bash"]
