source env.sh

# 创建kubelet bootstrap kubeconfig文件
echo "========创建kubelet bootstrap kubeconfig文件======="
for ((i=0; i<3; i++))
  do
    echo ">>> ${NODE_IPS[i]}"
    echo "创建token"
    export BOOTSTRAP_TOKEN=$(kubeadm token create \
      --description kubelet-bootstrap-token \
      --groups system:bootstrappers:${NODE_NAMES[i]} \
      --kubeconfig ~/.kube/config)
    
    echo "创建kubeconfig"
    # 设置集群参数
    kubectl config set-cluster kubernetes \
    --certificate-authority=/etc/kubernetes/cert/ca.pem \
    --server=${KUBE_APISERVER} \
    --kubeconfig=kubelet-bootstrap-${NODE_IPS[i]}.kubeconfig

    # 设置客户端认证参数
    kubectl config set-credentials kubelet-bootstrap \
    --token=${BOOTSTRAP_TOKEN} \
    --kubeconfig=kubelet-bootstrap-${NODE_IPS[i]}.kubeconfig

    # 设置上下文参数
    kubectl config set-context default \
    --cluster=kubernetes \
    --user=kubelet-bootstrap \
    --kubeconfig=kubelet-bootstrap-${NODE_IPS[i]}.kubeconfig

    # 设置默认上下文
    kubectl config use-context default \
    --kubeconfig=kubelet-bootstrap-${NODE_IPS[i]}.kubeconfig

    cat kubelet-bootstrap-${NODE_IPS[i]}.kubeconfig
  done

# 显示刚刚创建的bootstrap token
echo "=========显示刚刚创建的bootstrap token========="
kubeadm token list --kubeconfig ~/.kube/config

# 创建kubelet参数配置模板文件
echo "========创建kubelet参数配置模板文件======="
cat > kubelet.config.json.template <<EOF
{
    "kind": "KubeletConfiguration",
    "apiVersion": "kubelet.config.k8s.io/v1beta1",
    "authentication": {
        "x509": {
            "clientCAFile": "/etc/kubernetes/cert/ca.pem"
        },
        "webhook": {
            "enabled": true,
            "cacheTTL": "2m0s"
        },
        "anonymous": {
            "enabled": false
        }
    },
    "authorization": {
        "mode": "Webhook",
        "webhook": {
            "cacheAuthorizedTTL": "5m0s",
            "cacheUnauthorizedTTL": "30s"
        }
    },
    "address": "##NODE_IP##",
    "port": 10250,
    "readOnlyPort": 0,
    "cgroupDriver": "cgroupfs",
    "hairpinMode": "promiscuous-bridge",
    "serializeImagePulls": false,
    "featureGates": {
        "RotateKubeletClientCertificate": true,
        "RotateKubeletServerCertificate": true
    },
    "clusterDomain": "${CLUSTER_DNS_DOMAIN}",
    "clusterDNS": ["${CLUSTER_DNS_SVC_IP}"]
}
EOF
ls kubelet.config.json.template

# 创建kubelet参数配置文件
echo "========创建kubelet参数配置文件========="
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    sed -e "s/##NODE_IP##/${node_ip}/" \
      kubelet.config.json.template > \
      kubelet.config-${node_ip}.json
    ls kubelet.config-${node_ip}.json
  done

# 创建kubelet systemd service模板文件
echo "========创建kubelet systemd service模板文件======="
cat > kubelet.service.template <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/var/lib/kubelet
ExecStart=/opt/k8s/bin/kubelet \\
--bootstrap-kubeconfig=/etc/kubernetes/kubelet-bootstrap.kubeconfig\\
--cert-dir=/etc/kubernetes/cert \\
--kubeconfig=/etc/kubernetes/kubelet.kubeconfig \\
--config=/etc/kubernetes/kubelet.config.json \\
--hostname-override=##NODE_NAME## \\
--pod-infra-container-image=registry.access.redhat.com/rhel7/pod-infrastructure:latest \\
--allow-privileged=true \\
--alsologtostderr=true \\
--logtostderr=false \\
--log-dir=/var/log/kubernetes \\
--v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
ls kubelet.service.template

# 创建kubelet systemd service文件
echo "=========创建kubelet systemd service文件========="
for ((i=0; i<3; i++))
  do
    echo ">>> ${NODE_IPS[i]}"
    sed -e "s/##NODE_NAME##/${NODE_NAMES[i]}/" \
      kubelet.service.template > \
      kubelet-${NODE_IPS[i]}.service
  done

# 创建cluster role binding
#kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --group=system:bootstrappers

# 创建csr cluster role binding
cat > kubelet-crb.yaml <<EOF
# kubelet-bootstarp
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: kubelet-bootstrap
subjects:
  - kind: Group
    name: system:bootstrappers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: system:node-bootstrapper
  apiGroup: rbac.authorization.k8s.io
---
# Approve all CSRs for the group "system:bootstrappers"
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: auto-approve-csrs-for-group
subjects:
  - kind: Group
    name: system:bootstrappers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
  apiGroup: rbac.authorization.k8s.io
---
# To let a node of the group "system:nodes" renew its own credentials
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: node-client-cert-renewal
subjects:
  - kind: Group
    name: system:nodes
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
  apiGroup: rbac.authorization.k8s.io
---
# A ClusterRole which instructs the CSR approver to approve a node requesting a
# serving cert matching its client cert.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-server-renewal-csr
rules:
  - apiGroups: ["certificates.k8s.io"]
    resources: ["certificatesigningrequests/selfnodeserver"]
    verbs: ["create"]
---
# To let a node of the group "system:nodes" renew its own server credentials
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: node-server-cert-renewal
subjects:
  - kind: Group
    name: system:nodes
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: approve-node-server-renewal-csr
  apiGroup: rbac.authorization.k8s.io
EOF
ls kubelet-crb.yaml
kubectl apply -f kubelet-crb.yaml

# 分发并启动kubelet
echo "=========分发并启动kubelet======="
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    echo "分发kubelet二进制文件"
    ssh k8s@${node_ip} "sudo mkdir -p /opt/k8s/bin
                        sudo chown -R k8s:k8s /opt/k8s
                        if [ -f /opt/k8s/bin/kubelet ];then
                        sudo systemctl stop kubelet
                        rm -f /opt/k8s/bin/kubelet
                        fi"
    scp kubernetes/server/bin/kubelet k8s@${node_ip}:/opt/k8s/bin/

    echo "分发kubelet bootstrap kubeconfig文件"
    ssh k8s@${node_ip} "sudo mkdir -p /etc/kubernetes
                        sudo chown -R k8s:k8s /etc/kubernetes"
    scp kubelet-bootstrap-${node_ip}.kubeconfig \
      k8s@${node_ip}:/etc/kubernetes/kubelet-bootstrap.kubeconfig

    echo "分发kubelet参数配置文件"
    scp kubelet.config-${node_ip}.json \
      k8s@${node_ip}:/etc/kubernetes/kubelet.config.json

    echo "分发kubelet systemd service文件"
    scp kubelet-${node_ip}.service \
      root@${node_ip}:/usr/lib/systemd/system/kubelet.service

    echo "启动kubelet"
    ssh k8s@${node_ip} "sudo mkdir -p /var/lib/kubelet
                        sudo mkdir -p /var/log/kubernetes
                        sudo chown -R k8s:k8s /var/log/kubernetes
                        sudo /usr/sbin/swapoff -a
                        sudo systemctl daemon-reload
                        sudo systemctl enable kubelet
                        sudo systemctl start kubelet
                        sudo systemctl status kubelet | grep Active
                        sudo netstat -lnpt | grep kubelet"
  done

