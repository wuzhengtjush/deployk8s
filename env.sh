#!/usr/bin/bash

# 生成 EncryptionConfig 所需的加密 key
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

# 最好使用 当前未用的网段 来定义服务网段和 Pod 网段

# 服务网段，部署前路由不可达，部署后集群内路由可达(kube-proxy 和 ipvs 保证)
SERVICE_CIDR="10.254.0.0/16"

# Pod 网段，建议 /16 段地址，部署前路由不可达，部署后集群内路由可达(flanneld 保证)
CLUSTER_CIDR="172.30.0.0/16"

# 服务端口范围 (NodePort Range)
export NODE_PORT_RANGE="8400-9000"

# 集群master IP 数组
export MASTER_IPS=(192.168.6.211 192.168.6.212 192.168.6.213)

# 集群master 对应的 主机名数组
export MASTER_NAMES=(kube-master1 kube-master2 kube-master3)

# 集群node IP 数组
export NODE_IPS=(192.168.6.221 192.168.6.222 192.168.6.223)

# 集群node IP 对应的 主机名数组
export NODE_NAMES=(kube-node1 kube-node2 kube-node3)

# 集群master_node IP 数组（方便分发）
export MASTER_NODE_IPS=(192.168.6.211 192.168.6.212 192.168.6.213 192.168.6.221 192.168.6.222 192.168.6.223)

# kube-apiserver 的 VIP（HA 组件 keepalived 发布的 IP）
export MASTER_VIP=192.168.6.210

# kube-apiserver VIP 地址（HA 组件 haproxy 监听 8443 端口）
export KUBE_APISERVER="https://${MASTER_VIP}:8443"

# HA 节点，配置 VIP 的网络接口名称(ens33或者eth0)
export VIP_IF="ens33"

# etcd名字
export ETCD_NAMES=(etcd1 etcd2 etcd3) 
# etcd集群服务地址列表
export ETCD_ENDPOINTS="https://192.168.6.211:2379,https://192.168.6.212:2379,https://192.168.6.213:2379"
# etcd集群间通信的 IP 和端口
export ETCD_NODES="etcd1=https://192.168.6.211:2380,etcd2=https://192.168.6.212:2380,etcd3=https://192.168.6.213:2380"

# flanneld 网络配置前缀
export FLANNEL_ETCD_PREFIX="/kubernetes/network"

# kubernetes 服务 IP (一般是 SERVICE_CIDR 中第一个IP)
export CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"

# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
export CLUSTER_DNS_SVC_IP="10.254.0.2"

# 集群 DNS 域名
export CLUSTER_DNS_DOMAIN="cluster.local."

# 将二进制目录 /opt/k8s/bin 加到 PATH 中
# export PATH=/opt/k8s/bin:$PATH
