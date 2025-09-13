# KEDA Deployment using Helm

This project demonstrates **KEDA (Kubernetes Event Driven Autoscaler) deployment on Kubernetes** with modular ScaledObjects for auto-scaling workloads based on external metrics like RabbitMQ queue length.

---

## 📌 Features

- Helm-based KEDA installation with node affinity configuration
- Modular ScaledObjects per deployment for granular control
- RabbitMQ-based triggers for event-driven auto-scaling
- Support for secret-based authentication
- Horizontal Pod Autoscaler (HPA) integration
- Custom metrics and external scalers support

---

## 📂 Repository Structure

```
keda/
├── README.md              # This documentation
├── keda.sh                 # KEDA installation script
├── keda-affinity.yaml     # Node affinity configuration
└── scaled-object.yaml     # ScaledObject configuration example
```

---

## 🔧 Prerequisites

- **Kubernetes cluster** (v1.16+)
- **[Helm 3.x](https://helm.sh/docs/intro/install/)** installed and configured
- **RabbitMQ service** accessible from the cluster
- **kubectl** configured with cluster access
- **Metrics Server** installed in the cluster (for HPA functionality)

---

## 🚀 Installation Steps

### 1. Install KEDA

```bash
cd keda
bash keda.sh
```

### 2. Verify KEDA installation

```bash
kubectl get pods -n keda
kubectl get crd | grep keda
```

### 3. Apply a ScaledObject

```bash
kubectl apply -f scaled-object.yaml
```

### 4. Verify deployment

```bash
kubectl get scaledobjects -n demo-namespace
kubectl get pods -n demo-namespace
kubectl get hpa -n demo-namespace
```

---

## 📋 Configuration Examples

### Basic ScaledObject Structure

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: rabbitmq-scaledobject
  namespace: demo-namespace
spec:
  scaleTargetRef:
    name: your-deployment
  minReplicaCount: 1
  maxReplicaCount: 10
  triggers:
    - type: rabbitmq
      metadata:
        protocol: amqp
        queueName: task-queue
        queueLength: "5"
      authenticationRef:
        name: rabbitmq-secret
```

### Authentication Secret Example

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rabbitmq-secret
  namespace: demo-namespace
type: Opaque
data:
  host: <base64-encoded-rabbitmq-host>
  username: <base64-encoded-username>
  password: <base64-encoded-password>
```

---

## 🔍 Troubleshooting

### Check KEDA Operator Status

```bash
kubectl get pods -n keda
kubectl logs -f deployment/keda-operator -n keda
```

### Check ScaledObject Status

```bash
kubectl describe scaledobject <scaledobject-name> -n <namespace>
kubectl get hpa -n <namespace>
```

### Check Metrics

```bash
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1" | jq .
```

### Common Issues

1. **ScaledObject not scaling**: Check if the metrics server is running
2. **Authentication failures**: Verify secret configuration and network connectivity
3. **HPA conflicts**: Ensure no existing HPA targets the same deployment

---

## 🛠️ Advanced Configuration

### Node Affinity Configuration

The `keda-affinity.yaml` file contains node affinity rules to control where KEDA components are scheduled:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: node-type
              operator: In
              values:
                - worker
```

### Custom Scalers

KEDA supports various scalers including:

- Apache Kafka
- Azure Service Bus
- AWS SQS
- Prometheus
- Cron
- And many more...

---

## 📚 Reference Links

- [KEDA Official Documentation](https://keda.sh/)
- [ScaledObjects Concepts](https://keda.sh/docs/2.14/concepts/scaling-deployments/)
- [RabbitMQ Scaler Documentation](https://keda.sh/docs/2.14/scalers/rabbitmq-queue/)
- [Supported Scalers](https://keda.sh/docs/2.14/scalers/)
- [KEDA Helm Chart](https://artifacthub.io/packages/helm/kedacore/keda)
- [Kubernetes HPA Documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)

---
