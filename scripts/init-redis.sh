#!/bin/bash

cat <<EOF | kubectl --context $1 apply -f -
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-shared
data:
  update-node.sh: |+
    #!/bin/sh
    echo "Configuring node with NODE=\${NODE_NAME}, IP=\${POD_IP}..."
    CLUSTER_CONFIG="/data/nodes.conf"
    if [ -f \${CLUSTER_CONFIG} ]; then
      if [ -z "\${POD_IP}" ]; then 
        echo "Unable to determine Pod IP address!"
        exit 1
      fi
      echo "Updating my IP to \${POD_IP} in \${CLUSTER_CONFIG}"
      sed -i.bak -e "/myself/ s/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/\${POD_IP}/" \${CLUSTER_CONFIG}
    fi
    exec "\$@"
  redis.conf: |+
    cluster-enabled yes
    cluster-require-full-coverage no
    cluster-node-timeout 15000
    cluster-config-file /data/nodes.conf
    cluster-migration-barrier 1
    appendonly yes
    protected-mode no
    maxmemory 128mb
    maxmemory-policy allkeys-lru
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis-shared
spec:
  serviceName: redis-shared
  replicas: 1
  selector:
    matchLabels:
      app: redis-shared
      component: redis
  template:
    metadata:
      labels:
        app: redis-shared
        component: redis
    spec:
      containers:
      - name: redis
        image: redis:5-alpine
        ports:
        - containerPort: 6379
          name: client
        - containerPort: 16379
          name: gossip
        command: ["/conf/update-node.sh", "redis-server", "/conf/redis.conf"]
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        volumeMounts:
        - name: conf
          mountPath: /conf
          readOnly: false
        - name: data
          mountPath: /data
          readOnly: false
      volumes:
      - name: conf
        configMap:
          name: redis-shared
          defaultMode: 0755
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: "ssd"
      resources:
        requests:
          storage: 500Mi
---
apiVersion: v1
kind: Service
metadata:
  name: redis-shared
spec:
  type: ClusterIP
  selector:
    app: redis-shared
    component: redis
  ports:
  - port: 6379
    targetPort: 6379
    name: client
  - port: 16379
    targetPort: 16379
    name: gossip
EOF