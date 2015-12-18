name             'cdap'
maintainer       'Cask Data, Inc.'
maintainer_email 'ops@cask.co'
license          'Apache 2.0'
description      'Installs/Configures Cask Data Application Platform (CDAP)'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '2.17.1'

%w(apt ark hadoop java nodejs ntp yum yum-epel).each do |cb|
  depends cb
end

depends 'krb5_utils'

%w(amazon centos debian redhat scientific ubuntu).each do |os|
  supports os
end
