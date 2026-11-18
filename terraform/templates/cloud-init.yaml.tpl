#cloud-config
# Ubuntu: o DNS é do systemd-resolved (o módulo resolv_conf do cloud-init
# não roda no Ubuntu), então os servidores vão num drop-in do resolved.
write_files:
  - path: /etc/systemd/resolved.conf.d/10-dns.conf
    content: |
      [Resolve]
      DNS=${dns_primary} ${dns_secondary}

runcmd:
  - systemctl restart systemd-resolved

users:
  - name: mvrc
    groups: sudo
    shell: /bin/bash
    sudo: 'ALL=(ALL) NOPASSWD:ALL'
    ssh_authorized_keys:
%{ for key in ssh_keys ~}
      - ${key}
%{ endfor ~}
