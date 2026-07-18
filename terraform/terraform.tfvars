# Autenticação OCI (tenancy_ocid, user_ocid, fingerprint, private_key_path) e
# os caminhos das chaves SSH (my_ssh_public_key_path, jenkins_ssh_public_key_path)
# são injetados pelo Jenkins via variáveis TF_VAR_ - NUNCA preencha aqui
# (repo público).

# Região da tenancy
region = "sa-saopaulo-1"

# Compartment onde os recursos serão criados
compartment_ocid = "ocid1.compartment.oc1..REPLACE_WITH_YOUR_COMPARTMENT_OCID"

# VM (Always Free: shape AMD, 1 OCPU / 1GB RAM)
vm_name             = "oci-app-server"
shape               = "VM.Standard.E2.1.Micro"
boot_volume_size_gb = 50

# Rede
vcn_cidr    = "10.0.0.0/16"
subnet_cidr = "10.0.1.0/24"
