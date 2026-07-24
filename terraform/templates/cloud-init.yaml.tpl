#cloud-config
manage_resolv_conf: true
resolv_conf:
  nameservers:
    - ${dns_primary}
    - ${dns_secondary}

users:
  - name: mvrc
    groups: wheel
    shell: /bin/bash
    sudo: 'ALL=(ALL) NOPASSWD:ALL'
    ssh_authorized_keys:
%{ for key in ssh_keys ~}
      - ${key}
%{ endfor ~}
