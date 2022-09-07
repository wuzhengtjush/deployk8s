source env.sh

# haproxy启动服务
echo "==========haproxy启动服务=========="
for master_ip in ${MASTER_IPS[@]}
  do
    echo "启动haproxy服务"
    ssh root@${master_ip} "
      mkdir -p /var/lib/haproxy
      systemctl enable haproxy
      systemctl restart haproxy
      echo 'wait 3s for haproxy up'
      sleep 3
      systemctl status haproxy | grep Active
      netstat -lnpt | grep haproxy"
    if [ $? -ne 0 ];then echo "启动haproxy服务失败，退出脚本";exit 1;fi
  done


# 分发keepalived配置文件及启动
echo "==========分发keepalived配置文件及启动========"
for (( i=0; i < 3; i++ ))
  do
    echo ">>> ${MASTER_IPS[i]}"
    echo "启动keepalived服务，检查服务"
    ssh root@${MASTER_IPS[i]} "
      systemctl daemon-reload
      systemctl enable keepalived
      systemctl restart keepalived"

    echo "验证keepalived服务"
    if [ $i -eq 0 ]
    then
        echo 'wait 10s for setting vip'
        sleep 10
    else
        echo 'wait 3s for keepalived up'
        sleep 3
    fi
    ssh root@${MASTER_IPS[i]} "
      systemctl status keepalived | grep Active
      /usr/sbin/ip addr show ${VIP_IF}
      ping -c 3 ${MASTER_VIP}"
    if [ $? -ne 0 ];then echo "启动keepalived服务失败，退出脚本";exit 1;fi
  done

# 启动etcd
echo "=========分发并启动etcd=========="
for master_ip in ${MASTER_IPS[@]}
  do
    echo ">>> ${master_ip}"
    echo "启动etcd，首次启动这里会卡一段时间，不过不要紧"
    ssh root@${master_ip} "
      mkdir -p /var/lib/etcd
      systemctl daemon-reload
      systemctl enable etcd
      systemctl start etcd &
      systemctl status etcd | grep Active"
    if [ $? -ne 0 ];then echo "启动etcd失败，退出脚本";exit 1;fi
  done

# 分发etcdctl并验证etcd
echo "==========分发etcdctl==========="
for master_node_ip in ${MASTER_NODE_IPS[@]}
  do
    echo "${master_node_ip}验证etcd"
    ssh root@${master_node_ip} "
      ETCDCTL_API=3 etcdctl \
      --endpoints=${ETCD_ENDPOINTS} \
      --cacert=/etc/kubernetes/cert/ca.pem \
      --cert=/etc/etcdctl/cert/etcdctl.pem \
      --key=/etc/etcdctl/cert/etcdctl-key.pem \
      endpoint health"
    if [ $? -ne 0 ];then echo "分发etcdctl失败，退出脚本";exit 1;fi
  done

# 向etcd写入集群Pod网段信息
echo "=========向etcd写入集群Pod网段信息========="
etcdctl \
--endpoints=${ETCD_ENDPOINTS} \
--ca-file=/etc/kubernetes/cert/ca.pem \
--cert-file=${FLANNEL_PATH}/flanneld.pem \
--key-file=${FLANNEL_PATH}/flanneld-key.pem \
set ${FLANNEL_ETCD_PREFIX}/config '{"Network":"'${CLUSTER_CIDR}'", 
"SubnetLen": 24, "Backend": {"Type": "vxlan"}}'


# 启动flanneld
echo "=========分发并启动flanneld========"
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    echo "启动flanneld"
    ssh root@${node_ip} "
      systemctl daemon-reload
      systemctl enable flanneld
      systemctl start flanneld
      echo 'wait 5s for flanneld up'
      sleep 5
      systemctl status flanneld | grep Active"
    if [ $? -ne 0 ];then echo "启动flanneld失败，退出脚本";exit 1;fi

    echo "查看集群Pod网段"
    ssh root@${node_ip} "
      etcdctl \
      --endpoints=${ETCD_ENDPOINTS} \
      --ca-file=/etc/kubernetes/cert/ca.pem \
      --cert-file=/etc/flanneld/cert/flanneld.pem \
      --key-file=/etc/flanneld/cert/flanneld-key.pem \
      get ${FLANNEL_ETCD_PREFIX}/config"
    if [ $? -ne 0 ];then echo "查看集群Pod网段失败，退出脚本";exit 1;fi

    echo "查看已分配的Pod子网段列表"
    ssh root@${node_ip} "
      etcdctl \
      --endpoints=${ETCD_ENDPOINTS} \
      --ca-file=/etc/kubernetes/cert/ca.pem \
      --cert-file=/etc/flanneld/cert/flanneld.pem \
      --key-file=/etc/flanneld/cert/flanneld-key.pem \
      get ${FLANNEL_ETCD_PREFIX}/subnets"
    if [ $? -ne 0 ];then echo "查看已分配的Pod子网段列表失败，退出脚本";exit 1;fi

    echo "验证各节点能通过Pod网段互通"
    ssh root@${node_ip} "ip addr show flannel.1 | grep -w inet"
  done

  # 分发docker systemd service文件和启动
echo "========分发docker systemd service文件和启动========"
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    echo "启动docker"
    ssh root@${node_ip} "
      systemctl stop firewalld
      systemctl disable firewalld
      systemctl daemon-reload
      systemctl enable docker
      systemctl restart docker
      echo 'wait 3s for docker up'
      sleep 3
      systemctl status docker | grep Active
      /usr/sbin/ip addr show flannel.1
      /usr/sbin/ip addr show docker0"
    if [ $? -ne 0 ];then echo "启动docker失败，退出脚本";exit 1;fi
  done

# 分发并启动kube-apiserver
echo "========分发并启动kube-apiserver======="
for master_ip in ${MASTER_IPS[@]}
  do
    echo ">>> ${master_ip}"

    echo "启动kube-apiserver服务"
    ssh root@${master_ip} "
      mkdir -p /var/log/kubernetes
      systemctl daemon-reload
      systemctl enable kube-apiserver
      systemctl start kube-apiserver
      echo 'wait 5s for apiserver up'
      sleep 5
      systemctl status kube-apiserver | grep Active
      netstat -lnpt | grep kube-api"

    echo "查看kube-apiserver写入etcd的数据"
    ssh root@${master_ip} "
      ETCDCTL_API=3 etcdctl \
      --endpoints=${ETCD_ENDPOINTS} \
      --cacert=/etc/kubernetes/cert/ca.pem \
      --cert=/etc/etcdctl/cert/etcdctl.pem \
      --key=/etc/etcdctl/cert/etcdctl-key.pem \
      get /registry/ --prefix --keys-only"

    if [ $? -ne 0 ];then echo "启动kube-apiserver失败，退出脚本";exit 1;fi
  done

# 查看集群信息
echo "========查看集群信息========="
kubectl cluster-info

# 查看所有名字空间
echo "========查看所有名字空间========="
kubectl get all --all-namespaces

# 查看各组件状态
echo "========查看各组件状态========="
kubectl get componentstatuses

if [ $? -ne 0 ];then echo "执行kubectl命令失败，退出脚本";exit 1;fi

# 授予 kubernetes 证书访问 kubelet API 的权限
echo "========授予 kubernetes 证书访问 kubelet API 的权限========="
kubectl create clusterrolebinding \
kube-apiserver:kubelet-apis \
--clusterrole=system:kubelet-api-admin \
--user kubernetes
echo "ignore rolebindings alreadyExists"

# 分发controller-manager及启动
echo "=========分发controller-manager及启动========="
for master_ip in ${MASTER_IPS[@]}
  do
    echo ">>> ${master_ip}"
    echo "启动kube-controller-manager服务"
    ssh root@${master_ip} "
       mkdir -p /var/log/kubernetes
       systemctl daemon-reload
       systemctl enable kube-controller-manager
       systemctl start kube-controller-manager
       echo 'wait 5s for controller-mananger up'
       sleep 5
       systemctl status kube-controller-manager | grep Active
       netstat -lnpt | grep kube-con
       curl -s \
       --cacert /etc/kubernetes/cert/ca.pem \
       https://127.0.0.1:10252/metrics | head
       "
    if [ $? -ne 0 ];then echo "启动controller-manager失败，退出脚本";exit 1;fi

  done

# 查看当前的leader
echo "========查看当前的leader========="
kubectl get endpoints kube-controller-manager \
--namespace=kube-system \
-o yaml
if [ $? -ne 0 ];then echo "查看controller-manager的leader失败，退出脚本";exit 1;fi

# 分发scheduler及启动
echo "=========分发scheduler及启动========="
for master_ip in ${MASTER_IPS[@]}
  do
    echo ">>> ${master_ip}"
    echo "启动kube-scheduler服务"
    ssh root@${master_ip} "
      mkdir -p /var/log/kubernetes
      systemctl daemon-reload
      systemctl enable kube-scheduler
      systemctl start kube-scheduler
      echo 'wait 5s for scheduler up'
      sleep 5
      systemctl status kube-scheduler | grep Active
      netstat -lnpt | grep kube-sche
      echo '查看metric'
      curl -s http://127.0.0.1:10251/metrics | head"
    if [ $? -ne 0 ];then echo "启动scheduler失败，退出脚本";exit 1;fi

  done

# 查看当前的leader
echo "========查看当前的leader========="
kubectl get endpoints kube-scheduler \
--namespace=kube-system \
-o yaml
if [ $? -ne 0 ];then echo "查看scheduler的leader失败，退出脚本";exit 1;fi

# 分发并启动kubelet
echo "=========分发并启动kubelet======="
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    echo "启动kubelet"
    ssh root@${node_ip} "
      mkdir -p /var/lib/kubelet
      mkdir -p /var/log/kubernetes
      systemctl daemon-reload
      systemctl enable kubelet
      systemctl start kubelet
      echo 'wait 5s for kubelet up'
      sleep 5
      systemctl status kubelet | grep Active
      netstat -lnpt | grep kubelet"

    if [ $? -ne 0 ];then echo "启动kubelet失败，退出脚本";exit 1;fi
  done

# 分发kube-proxy并启动
echo "=======分发kube-proxy并启动========"
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    echo "分发kube-proxy二进制文件"

    echo "启动kube-proxy"
    ssh root@${node_ip} "
      mkdir -p /var/lib/kube-proxy
      mkdir -p /var/log/kubernetes
      systemctl daemon-reload
      systemctl enable kube-proxy
      systemctl start kube-proxy
      echo 'wait 5s for kube-proxy up'
      sleep 5
      systemctl status kube-proxy | grep Active
      netstat -lnpt | grep kube-pro"

    if [ $? -ne 0 ];then echo "启动kube-proxy失败，退出脚本";exit 1;fi
  done