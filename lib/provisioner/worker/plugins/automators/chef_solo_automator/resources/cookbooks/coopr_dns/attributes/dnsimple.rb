# Specify a fog version
default['dnsimple']['fog_version'] = '1.21.0'
# Our configuration
default['coopr_dns']['dnsimple']['databag_name'] = 'creds'
default['coopr_dns']['dnsimple']['databag_item'] = 'dnsimple'
# Ensure we run build-essential at compile-time
override['build-essential']['compile_time'] = true
