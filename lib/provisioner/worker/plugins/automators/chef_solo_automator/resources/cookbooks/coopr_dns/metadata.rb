name             'coopr_dns'
maintainer       'Cask Data, Inc.'
maintainer_email 'ops@cask.co'
license          'All rights reserved'
description      'Installs/Configures DNS'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.3.0'

depends 'dnsimple', '>= 2.0'
depends 'dynect'
