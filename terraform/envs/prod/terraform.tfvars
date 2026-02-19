project_id     = "ggn-nmfs-pamdata-prod-1"
region         = "us-east4"
zone           = "us-east4-c"
environment    = "prod"
application_id = "pamdata"
line_office    = "nmfs"
system_id      = "noaa4000"
task_order     = "13051420fnffk0123"
network_prefix = "app"

# ── Subnets ───────────────────────────────────────────────────────────────────
app_subnet1_cidr  = "10.1.0.0/26"
app_subnet2_cidr  = "10.1.0.64/26"
db_subnet1_cidr   = "10.2.0.0/26"
batch_subnet_cidr = "10.3.0.0/16"

# ── IAM / Principals ──────────────────────────────────────────────────────────
pamdata_admin = [
  "user:daniel.woodrich@noaa.gov",
  "user:jeffrey.walker@noaa.gov",
]

pamdata_supervisors = [
  "user:sofie.vanparijs@noaa.gov",
  "user:rebecca.vanhoeck@noaa.gov",
]

app_developers = ["user:daniel.woodrich@noaa.gov"]

transfer_appliance_admins = ["user:rebecca.vanhoeck@noaa.gov"]

transfer_appliance_users = [
  "user:thomas.sejkora@noaa.gov",
  "user:daniel.woodrich@noaa.gov",
]

nefsc_minke_detector_users = [
  "user:daniel.woodrich@noaa.gov",
  "user:lindsey.transue@noaa.gov",
  "serviceAccount:composer-sa1@ggn-nmfs-pamarc-dev-1.iam.gserviceaccount.com",
]

nefsc_humpback_detector_users = [
  "user:daniel.woodrich@noaa.gov",
  "user:lindsey.transue@noaa.gov",
  "serviceAccount:composer-sa1@ggn-nmfs-pamarc-dev-1.iam.gserviceaccount.com",
]

afsc_instinct_users = [
  "user:daniel.woodrich@noaa.gov",
  "serviceAccount:composer-sa1@ggn-nmfs-pamarc-dev-1.iam.gserviceaccount.com",
  "serviceAccount:afsc-instinct@ggn-nmfs-pamdata-prod-1.iam.gserviceaccount.com",
]

transfer_appliance_service_accounts = [
  "serviceAccount:ta-c0-e326-9133@transfer-appliance-zimbru.iam.gserviceaccount.com",
  "serviceAccount:project-804870724004@storage-transfer-service.iam.gserviceaccount.com",
]

# ── Storage ───────────────────────────────────────────────────────────────────
data_buckets_map = {
  "omms-1" = {
    data_authority = "user:timothy.rowell@noaa.gov"
    data_admins = [
      "user:timothy.rowell@noaa.gov",
      "user:lindsey.peavey@noaa.gov",
      "user:eden.zangl@noaa.gov",
      "user:anastasia.kurz@noaa.gov",
      "user:samara.m.havern@noaa.gov",
      "user:emma.berretta@noaa.gov",
    ]
    all_users = []
  }
  "afsc-1" = {
    data_authority = "user:catherine.berchok@noaa.gov"
    data_admins = [
      "user:daniel.woodrich@noaa.gov",
      "user:catherine.berchok@noaa.gov",
    ]
    all_users = ["group:nmfs.afsc.nml.acoustics@noaa.gov"]
  }
  "nefsc-1" = {
    data_authority = "user:sofie.vanparijs@noaa.gov"
    data_admins = [
      "user:julianne.wilder@noaa.gov",
      "user:kate.choate@noaa.gov",
      "user:xavier.mouy@noaa.gov",
      "user:david.chevrier@noaa.gov",
      "user:timothy.rowell@noaa.gov",
      "user:taiki.sakai@noaa.gov",
      "user:catherine.dodge@noaa.gov",
    ]
    all_users = [
      "user:kate.choate@noaa.gov",
      "user:lindsey.transue@noaa.gov",
      "user:rebecca.vanhoek@noaa.gov",
      "user:irene.brinkman@noaa.gov",
      "user:rhett.finley@noaa.gov",
      "user:sofie.vanparijs@noaa.gov",
      "user:jeffrey.walker@noaa.gov",
      "user:jessica.mccormick@noaa.gov",
    ]
  }
  "sefsc-1" = {
    data_authority = "user:melissa.soldevilla@noaa.gov"
    data_admins = [
      "user:melissa.soldevilla@noaa.gov",
      "user:heloise.trouin-nouy@noaa.gov",
    ]
    all_users = [
      "group:nmfs.sefsc.mmt.pam-ecology@noaa.gov",
      "user:lia.caldwell@noaa.gov",
    ]
  }
  "afsc-2" = {
    data_authority = "user:timothy.rowell@noaa.gov"
    data_admins = [
      "user:timothy.rowell@noaa.gov",
      "user:matt.grossi@noaa.gov",
      "user:amelia.johnson@noaa.gov",
    ]
    all_users = []
  }
  "swfsc-1" = {
    data_authority = "user:shannon.rankin@noaa.gov"
    data_admins = [
      "user:kourtney.burger@noaa.gov",
      "user:shannon.rankin@noaa.gov",
    ]
    all_users = []
  }
  "nmfsc-1" = {
    data_authority = "user:marla.holt@noaa.gov"
    data_admins = [
      "user:marla.holt@noaa.gov",
      "user:candice.emmons@noaa.gov",
      "user:arial.brewer@noaa.gov",
    ]
    all_users = []
  }
  "nmfsc-2" = {
    data_authority = "user:candice.emmons@noaa.gov"
    data_admins = [
      "user:candice.emmons@noaa.gov",
      "user:marla.holt@noaa.gov",
      "user:arial.brewer@noaa.gov",
    ]
    all_users = []
  }
  "pifsc-1" = {
    data_authority = "user:ann.allen@noaa.gov"
    data_admins = [
      "user:jennifer.mccullough@noaa.gov",
      "user:ann.allen@noaa.gov",
      "user:karlina.berkness@noaa.gov",
      "user:selene.fregosi@noaa.gov",
      "user:jenny.trickey@noaa.gov",
    ]
    all_users = ["user:kourtney.burger@noaa.gov"]
  }
  "ost-1" = {
    data_authority = "user:jason.gedeon@noaa.gov"
    data_admins = [
      "user:samara.m.havern@noaa.gov",
      "user:lauren.k.rodgers@noaa.gov",
      "user:angela.treas@noaa.gov",
      "user:margi.swords@noaa.gov",
      "user:julianne.wilder@noaa.gov",
      "user:kate.choate@noaa.gov",
    ]
    all_users = ["user:samara.m.havern@noaa.gov"]
  }
  "pffs-collaborative" = {
    data_authority = ""
    data_admins    = ["group:nmfs.pam-gilders@noaa.gov"]
    all_users      = ["group:nmfs.pam-gilders@noaa.gov"]
  }
}
