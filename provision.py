#!/usr/bin/env python3
"""
Phase 1 — no VPN yet.

Terraform apply for rke2-{management|dev|prod}, VPC peering, OpenVPN via Ansible
(management only), then fetch kubeconfig over SSH through the OpenVPN jump host.

Usage:
    ./provision.py [management|dev|prod]     (default: management)

Then:
    sudo openvpn --config ansible/out/devops.ovpn
    ./configure.py management
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
import time

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TERRAFORM_DIR = os.path.join(_SCRIPT_DIR, "terraform")
ANSIBLE_DIR = os.path.join(_SCRIPT_DIR, "ansible")
_VALID = ("dev", "prod", "management")
SSH_OPTS = (
    "-o IdentitiesOnly=yes -o StrictHostKeyChecking=no "
    "-o ConnectTimeout=60 -o ConnectionAttempts=3 -o AddressFamily=inet "
    "-o ControlMaster=no -o ServerAliveInterval=15 -o ServerAliveCountMax=4"
)


def _env_name() -> str:
    if len(sys.argv) >= 2:
        env = sys.argv[1].lower()
        if env not in _VALID:
            print(f"Usage: {sys.argv[0]} [management|dev|prod]", file=sys.stderr)
            sys.exit(1)
        return env
    return os.environ.get("TF_ENV", "management")


TF_ENV = _env_name()
STACK = f"rke2-{TF_ENV}"
STACK_DIR = os.path.join(TERRAFORM_DIR, "environments", STACK)
KUBECONFIG_FILE = os.path.join(_SCRIPT_DIR, f"kube_config_rke2_{TF_ENV}.yaml")
KEY_FILE = os.path.join(STACK_DIR, f"rke2-key-{TF_ENV}.pem")
MGMT_KEY = os.path.join(TERRAFORM_DIR, "environments", "rke2-management", "rke2-key-management.pem")


def run(cmd: str, cwd=None, env=None, timeout=None) -> None:
    print(f"Running: {cmd}")
    try:
        subprocess.run(cmd, shell=True, cwd=cwd, env=env, check=True, timeout=timeout)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        print(f"Error: {exc}")
        sys.exit(1)


def tf_output() -> dict:
    raw = subprocess.check_output(
        f"terraform -chdir=environments/{STACK} output -json",
        shell=True,
        cwd=TERRAFORM_DIR,
    )
    return json.loads(raw)


def mgmt_openvpn_ip() -> str:
    raw = subprocess.check_output(
        "terraform -chdir=environments/rke2-management output -json",
        shell=True,
        cwd=TERRAFORM_DIR,
        timeout=30,
    )
    data = json.loads(raw)
    return data.get("openvpn_public_ip", {}).get("value", "") or ""


def setup_terraform() -> None:
    tfvars = os.path.join(STACK_DIR, "terraform.tfvars")
    example = os.path.join(STACK_DIR, "terraform.tfvars.example")
    if not os.path.isfile(tfvars) and os.path.isfile(example):
        with open(example) as src, open(tfvars, "w") as dst:
            dst.write(src.read())
        print(f"Created {tfvars} from example")
    print("--- Terraform apply ---")
    run(f"terraform -chdir=environments/{STACK} init -input=false", cwd=TERRAFORM_DIR)
    run(
        f"terraform -chdir=environments/{STACK} apply -auto-approve -input=false -var-file=terraform.tfvars",
        cwd=TERRAFORM_DIR,
    )


def setup_networking() -> None:
    if os.environ.get("SKIP_NETWORKING") == "1" or TF_ENV == "management":
        return
    print("--- VPC peering ---")
    run("terraform -chdir=environments/networking init -input=false", cwd=TERRAFORM_DIR)
    run("terraform -chdir=environments/networking apply -auto-approve -input=false", cwd=TERRAFORM_DIR)


def run_openvpn_ansible(public_ip: str) -> None:
    print("--- Ansible OpenVPN ---")
    key = os.path.abspath(MGMT_KEY if os.path.isfile(MGMT_KEY) else KEY_FILE)
    probe = (
        f"ssh -i {shlex.quote(key)} {SSH_OPTS} ubuntu@{public_ip} echo ready"
    )
    ok = False
    for waited in range(0, 300, 10):
        res = subprocess.run(probe, shell=True, capture_output=True, timeout=90)
        if res.returncode == 0 and b"ready" in (res.stdout or b""):
            print(f"  SSH ready ({waited}s)")
            ok = True
            break
        time.sleep(10)
    if not ok:
        print(f"  SSH timeout. Try: {probe}")
        sys.exit(1)

    inventory = os.path.join(ANSIBLE_DIR, "inventory_openvpn.yml")
    with open(inventory, "w") as f:
        f.write(
            "vpn_server:\n"
            "  hosts:\n"
            "    openvpn:\n"
            f"      ansible_host: {public_ip}\n"
            "      ansible_user: ubuntu\n"
            f"      ansible_ssh_private_key_file: {key}\n"
        )
    users = os.path.join(ANSIBLE_DIR, "group_vars", "users.yml")
    example = os.path.join(ANSIBLE_DIR, "group_vars", "users.yml.example")
    if not os.path.isfile(users):
        print(f"  Copy {example} → group_vars/users.yml and fill ssh_public_key, then re-run.")
        sys.exit(1)
    env = os.environ.copy()
    env["ANSIBLE_HOST_KEY_CHECKING"] = "False"
    run(
        f"ansible-playbook -i inventory_openvpn.yml "
        f"-e openvpn_public_ip={public_ip} openvpn-server.yml",
        cwd=ANSIBLE_DIR,
        env=env,
        timeout=600,
    )


def fetch_kubeconfig(jump_ip: str, jump_key: str, master_ip: str, node_key: str, api_dns: str) -> None:
    print("--- Fetch kubeconfig via OpenVPN jump ---")
    inner = (
        f"ssh -i ~/.ssh/rke2-key.pem -o IdentitiesOnly=yes -o StrictHostKeyChecking=no "
        f"-o ConnectTimeout=10 ubuntu@{master_ip}"
    )
    with open(node_key, "rb") as f:
        key_bytes = f.read()
    remote = "mkdir -p /home/ubuntu/.ssh && chmod 700 /home/ubuntu/.ssh && cat > /home/ubuntu/.ssh/rke2-key.pem && chmod 600 /home/ubuntu/.ssh/rke2-key.pem"
    ssh = ["ssh", "-T", "-i", jump_key] + shlex.split(SSH_OPTS) + [
        f"ubuntu@{jump_ip}",
        f"/bin/bash -c {shlex.quote(remote)}",
    ]
    res = subprocess.run(ssh, input=key_bytes, capture_output=True, timeout=90)
    if res.returncode != 0:
        print((res.stderr or b"").decode(errors="replace")[:400])
        sys.exit(1)

    content = None
    for waited in range(0, 420, 15):
        try:
            content = subprocess.check_output(
                f"ssh -i {shlex.quote(jump_key)} {SSH_OPTS} ubuntu@{jump_ip} "
                f"'{inner} sudo cat /etc/rancher/rke2/rke2.yaml'",
                shell=True,
                timeout=90,
            )
            if content:
                print(f"  kubeconfig ready ({waited}s)")
                break
        except subprocess.CalledProcessError:
            pass
        time.sleep(15)
    if not content:
        print("  Could not read rke2.yaml")
        sys.exit(1)

    text = content.decode()
    text = re.sub(r"server:\s*https://[^\s\n]+", f"server: https://{api_dns}:6443", text)
    with open(KUBECONFIG_FILE, "w") as f:
        f.write(text)
    os.chmod(KUBECONFIG_FILE, 0o600)
    print(f"  wrote {KUBECONFIG_FILE} (server https://{api_dns}:6443 — VPN required)")


def main() -> None:
    print(f"PROVISION rke2-{TF_ENV}")
    if os.environ.get("SKIP_TERRAFORM") != "1":
        setup_terraform()
        if TF_ENV != "management":
            setup_networking()

    out = tf_output()
    api_dns = out["api_dns_name"]["value"]
    master_ip = out["master_private_ips"]["value"][0]

    if TF_ENV == "management":
        jump_ip = out["openvpn_public_ip"]["value"]
        jump_key = os.path.abspath(KEY_FILE)
        run_openvpn_ansible(jump_ip)
    else:
        jump_ip = mgmt_openvpn_ip()
        jump_key = os.path.abspath(MGMT_KEY)
        if not jump_ip or not os.path.isfile(jump_key):
            print("Need provision.py management first (OpenVPN jump).")
            sys.exit(1)

    fetch_kubeconfig(jump_ip, jump_key, master_ip, os.path.abspath(KEY_FILE), api_dns)
    print(f"\nNext: sudo openvpn --config ansible/out/devops.ovpn")
    print(f"      export KUBECONFIG={os.path.abspath(KUBECONFIG_FILE)}")
    print(f"      ./configure.py {TF_ENV}")


if __name__ == "__main__":
    main()
