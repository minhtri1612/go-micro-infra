#!/usr/bin/env python3
"""
Phase 2 — VPN required.

Management: EBS CSI, Argo CD, bootstrap (projects + kube-prometheus-stack).
Dev/prod:   EBS CSI, External Secrets Operator.

Usage:
    ./configure.py [management|dev|prod]     (default: management)
    ./configure.py prod --skip-vpn-check
"""
from __future__ import annotations

import os
import re
import shlex
import socket
import subprocess
import sys
import time

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TERRAFORM_DIR = os.path.join(_SCRIPT_DIR, "terraform")
_VALID = ("dev", "prod", "management")
HOSTS = {
    "management": ("argocd.local", "grafana.go-micro.local"),
    "dev": ("dev.go-micro.local",),
    "prod": ("go-micro.local",),
}


def _strip_flags() -> None:
    if len(sys.argv) < 2:
        return
    kept = [sys.argv[0]]
    for arg in sys.argv[1:]:
        if arg in ("--skip-vpn-check", "-S"):
            os.environ["SKIP_VPN_CHECK"] = "1"
            continue
        kept.append(arg)
    sys.argv[:] = kept


_strip_flags()


def _env_name() -> str:
    if len(sys.argv) >= 2:
        env = sys.argv[1].lower()
        if env not in _VALID:
            print(f"Usage: {sys.argv[0]} [management|dev|prod] [--skip-vpn-check]", file=sys.stderr)
            sys.exit(1)
        return env
    return os.environ.get("TF_ENV", "management")


TF_ENV = _env_name()
STACK = f"rke2-{TF_ENV}"
KUBECONFIG_FILE = os.path.join(_SCRIPT_DIR, f"kube_config_rke2_{TF_ENV}.yaml")
GITOPS_DIR = os.environ.get(
    "GO_MICRO_GITOPS",
    os.path.abspath(os.path.join(_SCRIPT_DIR, "..", "go-micro-gitops")),
)


def run(cmd: str, cwd=None, env=None, timeout=None) -> None:
    print(f"Running: {cmd}")
    try:
        subprocess.run(cmd, shell=True, cwd=cwd, env=env, check=True, timeout=timeout)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        print(f"Error: {exc}")
        sys.exit(1)


def kube_env() -> dict:
    env = os.environ.copy()
    env["KUBECONFIG"] = os.path.abspath(KUBECONFIG_FILE)
    return env


def tf_output() -> dict:
    raw = subprocess.check_output(
        f"terraform -chdir=environments/{STACK} output -json",
        shell=True,
        cwd=TERRAFORM_DIR,
    )
    return json.loads(raw)


def _apiserver_host_port(path: str):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
        m = re.search(r"server:\s*https?://([^:/\s]+):(\d+)", text)
        if m:
            return m.group(1), int(m.group(2))
    except OSError:
        pass
    return None, None


def check_vpn() -> None:
    if os.environ.get("SKIP_VPN_CHECK") == "1":
        print("  skip VPN check")
        return
    if not os.path.isfile(KUBECONFIG_FILE):
        print(f"Missing {KUBECONFIG_FILE} — run ./provision.py {TF_ENV} first")
        sys.exit(1)
    host, port = _apiserver_host_port(KUBECONFIG_FILE)
    if host and port:
        try:
            s = socket.create_connection((host, port), timeout=10)
            s.close()
        except OSError:
            print(f"Cannot reach apiserver {host}:{port}. Enable VPN, then retry.")
            sys.exit(1)
        print(f"  apiserver {host}:{port} reachable")
    res = subprocess.run(
        f"kubectl --kubeconfig={shlex.quote(KUBECONFIG_FILE)} get nodes --request-timeout=20s",
        shell=True,
        capture_output=True,
        timeout=45,
    )
    if res.returncode != 0:
        print((res.stderr or res.stdout or b"").decode(errors="replace")[:400])
        sys.exit(1)
    print("  kubectl get nodes OK")


def install_ebs_csi() -> None:
    print("--- EBS CSI ---")
    env = kube_env()
    run("helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver", env=env)
    run("helm repo update aws-ebs-csi-driver", env=env)
    run(
        "helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver "
        "--namespace kube-system --create-namespace --timeout 10m",
        env=env,
    )


def install_argocd() -> None:
    print("--- Argo CD ---")
    env = kube_env()
    values = os.path.join(_SCRIPT_DIR, "kind", "argocd-values.yaml")
    run("helm repo add argo https://argoproj.github.io/argo-helm", env=env)
    subprocess.run("helm repo update argo", shell=True, env=env, capture_output=True)
    run(
        f"helm upgrade --install argocd argo/argo-cd "
        f"--namespace argocd --create-namespace "
        f"--values {shlex.quote(values)} --timeout 10m",
        env=env,
    )
    for _ in range(30):
        r = subprocess.run(
            "kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server "
            "-o jsonpath='{.items[*].status.containerStatuses[0].ready}'",
            shell=True,
            env=env,
            capture_output=True,
            text=True,
            timeout=15,
        )
        if "true" in (r.stdout or ""):
            print("  Argo CD server ready")
            return
        time.sleep(10)
    print("  Argo CD not ready after 300s — continuing")


def deploy_bootstrap() -> None:
    print("--- Argo CD bootstrap (projects + monitoring on management) ---")
    env = kube_env()
    bootstrap = os.path.join(GITOPS_DIR, "argocd", "bootstrap")
    if not os.path.isdir(bootstrap):
        print(f"Missing {bootstrap}. Clone go-micro-gitops next to go-micro-infra or set GO_MICRO_GITOPS.")
        sys.exit(1)
    # Management only: projects + kube-prometheus-stack. Dest/prod apps wait until
    # `argocd cluster add`.
    names = [
        "00-argocd-cm-health.yaml",
        "01-projects.yaml",
        "05-monitoring-mgmt.yaml",
    ]
    for name in names:
        path = os.path.join(bootstrap, name)
        if os.path.isfile(path):
            run(f"kubectl apply -f {shlex.quote(path)}", env=env, timeout=60)
        else:
            print(f"  skip missing {name}")
    print("  Grafana NodePort 32000 / Prometheus 32090 / Argo CD 30443")


def install_eso() -> None:
    print("--- External Secrets Operator ---")
    env = kube_env()
    run("helm repo add external-secrets https://charts.external-secrets.io", env=env)
    run("helm repo update external-secrets", env=env)
    run(
        "helm upgrade --install external-secrets external-secrets/external-secrets "
        "-n external-secrets --create-namespace --set installCRDs=true --timeout 5m",
        env=env,
    )
    run(
        "kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -",
        env=env,
    )
    access = subprocess.check_output(
        f"terraform -chdir=environments/{STACK} output -raw eso_access_key_id",
        shell=True,
        cwd=TERRAFORM_DIR,
        text=True,
    ).strip()
    secret = subprocess.check_output(
        f"terraform -chdir=environments/{STACK} output -raw eso_secret_access_key",
        shell=True,
        cwd=TERRAFORM_DIR,
        text=True,
    ).strip()
    run(
        "kubectl create secret generic aws-credentials -n external-secrets "
        f"--from-literal=access-key-id={shlex.quote(access)} "
        f"--from-literal=secret-access-key={shlex.quote(secret)} "
        "--dry-run=client -o yaml | kubectl apply -f -",
        env=env,
    )


def update_hosts(nlb_dns: str) -> None:
    if not nlb_dns:
        return
    try:
        ip = socket.gethostbyname(nlb_dns)
    except OSError:
        print(f"  could not resolve {nlb_dns}")
        return
    names = " ".join(HOSTS.get(TF_ENV, ()))
    print(f"  add to /etc/hosts: {ip}  {names}")


def main() -> None:
    print(f"CONFIGURE rke2-{TF_ENV} (VPN required)")
    check_vpn()
    install_ebs_csi()
    if TF_ENV == "management":
        install_argocd()
        deploy_bootstrap()
        print("\nJenkins is compose on the management VPC EC2, not a pod:")
        print("  terraform -chdir=terraform/environments/rke2-management output jenkins_url")
        print("Argo CD: https://<web_nlb>:443  (NodePort 30443)")
        print("Grafana: http://<web_nlb>:32000   Prometheus: http://<web_nlb>:32090")
    else:
        install_eso()
        print("Register this cluster with Argo CD (VPN + management kubeconfig):")
        print(f"  argocd cluster add <ctx> --name {TF_ENV} --kubeconfig {KUBECONFIG_FILE} --insecure --yes")
    nlb = tf_output().get("web_dns_name", {}).get("value", "")
    update_hosts(nlb)


if __name__ == "__main__":
    main()
