name             'coopr_hosts'
maintainer       'Cask Data, Inc.'
maintainer_email 'ops@cask.co'
license          'Apache-2.0'
description      'Installs/Configures /etc/hosts'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.1.1'

depends 'hostsfile'
