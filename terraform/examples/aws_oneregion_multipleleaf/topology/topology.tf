module "globals" {
  source = "../../../module/arista/common"
  topology = var.topology
  keypair_name = var.keypair_name
  cvaas = var.cvaas
  instance_type = var.instance_type
  aws_regions = var.aws_regions
  eos_amis = var.eos_amis
  availability_zone = var.availability_zone
  host_amis = var.host_amis
}

provider "aws" {
  region = module.globals.aws_regions["region1"]
}

provider "arista" {
  cvaas_domain = module.globals.cvaas["domain"]
  cvaas_username = module.globals.cvaas["username"]
  cvaas_server = module.globals.cvaas["server"]
  service_account_web_token = module.globals.cvaas["service_token"]
}

resource "arista_topology" "topology" {
  topology_name           = module.globals.topology
  bgp_asn                 = "65200-65300" // Range of BGP ASN’s used for topology
  vtep_ip_cidr            = "8.0.0.0/16"  // CIDR block for VTEP IPs on veos
  terminattr_ip_cidr      = "9.0.0.0/16"  // Loopback IP range on veos
  dps_controlplane_cidr   = "11.0.0.0/16"  // CIDR block for Dps Control Plane IPs on veos
}
resource "arista_clos" "clos" {
  name              = "${module.globals.topology}-clos"
  topology_name     = arista_topology.topology.topology_name
  cv_container_name = var.clos_cv_container
}

resource "arista_wan" "wan" {
  name              = "${module.globals.topology}-wan"
  topology_name     = arista_topology.topology.topology_name
  cv_container_name = var.wan_cv_container
}

module "RRVpc" {
  source        = "../../../module/arista/aws/vpc"
  topology_name = arista_topology.topology.topology_name
  clos_name     = arista_clos.clos.name
  wan_name      = arista_wan.wan.name
  role          = "CloudEdge"
  igw_name      = "${module.globals.topology}-RRVpcIgw"
  cidr_block    = ["10.0.0.0/16"]
  tags = {
    Name = "${module.globals.topology}-RRVpc"
    Cnps = "Dev"
  }
  region = module.globals.aws_regions["region1"]
}

module "RRSubnet" {
  source = "../../../module/arista/aws/subnet"
  subnet_zones = {
    "10.0.0.0/24" = lookup( module.globals.availability_zone[module.RRVpc.region], "zone1", "" )
    "10.0.1.0/24" = lookup( module.globals.availability_zone[module.RRVpc.region], "zone2", "" )
  }
  subnet_names = {
    "10.0.0.0/24" = "${module.globals.topology}-RRSubnet0"
    "10.0.1.0/24" = "${module.globals.topology}-RR2Subnet0"
  }
  vpc_id        = module.RRVpc.vpc_id[0]
  topology_name = module.RRVpc.topology_name
  region = module.globals.aws_regions["region1"]
}

module "CloudEOSRR1" {
  source = "../../../module/arista/aws/cloudEOS"
  role = "CloudEdge"
  topology_name = module.RRVpc.topology_name
  cloudeos_ami = module.globals.eos_amis[module.RRVpc.region]
  keypair_name = module.globals.keypair_name[module.RRVpc.region]
  vpc_info = module.RRVpc.vpc_info
  intf_names = ["${module.globals.topology}-RRIntf0"]
  interface_types = {
    "${module.globals.topology}-RRIntf0" = "public"
  }
  subnetids = {
    "${module.globals.topology}-RRIntf0" = module.RRSubnet.vpc_subnets[0]
  }
  private_ips = {
    "0": ["10.0.0.101"]
  }
  availability_zone = lookup( module.globals.availability_zone[module.RRVpc.region], "zone1", "" )
  region = module.RRVpc.region
  tags = {
    "Name" = "${module.globals.topology}-CloudEosRR1"
    "RouteReflector" = "True"
  }
  is_rr = true
  primary = true
  filename = "../../../userdata/eos_ipsec_config.tpl"
}
module "CloudEOSRR2" {
  source = "../../../module/arista/aws/cloudEOS"
  role = "CloudEdge"
  topology_name = module.RRVpc.topology_name
  cloudeos_ami = module.globals.eos_amis[module.RRVpc.region]
  keypair_name = module.globals.keypair_name[module.RRVpc.region]
  vpc_info = module.RRVpc.vpc_info
  intf_names = ["${module.globals.topology}-RR2Intf0"]
  interface_types = {
    "${module.globals.topology}-RR2Intf0" = "public"
  }
  subnetids = {
    "${module.globals.topology}-RR2Intf0" = module.RRSubnet.vpc_subnets[1]
  }
  private_ips = {
    "0": ["10.0.1.101"]
  }
  availability_zone = lookup( module.globals.availability_zone[module.RRVpc.region], "zone2", "" )
  region = module.RRVpc.region
  tags = {
    "Name" = "${module.globals.topology}-CloudEosRR2"
    "RouteReflector" = "True"
  }
  is_rr = true
  primary = true
  filename = "../../../userdata/eos_ipsec_config.tpl"
}
