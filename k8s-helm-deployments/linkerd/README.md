# 🚀 Linkerd Installation Guide (EKS + Custom Certificates)

This repository provides step-by-step instructions and example manifests
to install **Linkerd** on AWS EKS using both **default installation** and **custom certificates**.

---

## 1️⃣ Pre-requisites

- Access to an EKS cluster
- AWS CLI + `aws-iam-authenticator`
- `kubectl`, `helm`, and `linkerd` CLI installed

Verify AWS access:

```bash
aws sts get-caller-identity
```

---

## 2️⃣ Linkerd CLI Installation

```bash
curl -sL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin

linkerd version
linkerd check --pre
```

Install Linkerd:

```bash
linkerd install | kubectl apply -f -
linkerd check
```

Verify:

```bash
kubectl -n linkerd get deploy
linkerd dashboard &
```

Inject Linkerd sidecars:

```bash
kubectl -n emojivoto get deploy -o yaml | linkerd inject - | kubectl apply -f -
```

---

## 3️⃣ Custom Certificates Setup (Step CLI)

```bash
brew install step
step certificate create root.linkerd.cluster.local ca.crt ca.key \
  --profile root-ca --not-after 8760h --no-password --insecure

step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
  --profile intermediate-ca --not-after 87600h \
  --no-password --insecure \
  --ca ca.crt --ca-key ca.key
```

---

## 4️⃣ Reinstall Linkerd with Certificates

```bash
linkerd uninstall | kubectl delete -f -

linkerd install \
  --identity-trust-anchors-file certs/ca.crt \
  --identity-issuer-certificate-file certs/issuer.crt \
  --identity-issuer-key-file certs/issuer.key \
  | kubectl apply -f -
```

Validate:

```bash
openssl x509 -in certs/issuer.crt -noout -text | grep 'Not'
```

---

## 5️⃣ Namespace & Pod Injection

Enable auto-injection:

```bash
kubectl annotate ns test linkerd.io/inject=enabled
```

Check secure edges:

```bash
linkerd -n test edges deployment
```

Skip specific ports (example PostgreSQL):

```yaml
annotations:
  config.linkerd.io/skip-inbound-ports: "5432"
  config.linkerd.io/skip-outbound-ports: "5432"
```

---

## 6️⃣ Helm Installation

### Legacy:

```bash
helm repo add linkerd https://helm.linkerd.io/stable
helm install linkerd2 --version 2.10.0 \
  --set-file global.identityTrustAnchorsPEM=certs/ca.crt \
  --set-file identity.issuer.tls.crtPEM=certs/issuer.crt \
  --set-file identity.issuer.tls.keyPEM=certs/issuer.key \
  linkerd/linkerd2
```

### Latest (1.16.x):

```bash
helm repo add linkerd https://helm.linkerd.io/stable

helm install linkerd-crds linkerd/linkerd-crds \
  -n linkerd --create-namespace

helm install linkerd-control-plane --version 1.16.6 \
  -n linkerd \
  --set-file identityTrustAnchorsPEM=certs/ca.crt \
  --set-file identity.issuer.tls.crtPEM=certs/issuer.crt \
  --set-file identity.issuer.tls.keyPEM=certs/issuer.key \
  linkerd/linkerd-control-plane
```

---

## 7️⃣ Verification

```bash
linkerd check --proxy --verbose
kubectl -n linkerd get pods
```
