#
# Cookbook Name:: cdap
# Recipe:: default
#
# Copyright © 2013-2014 Cask Data, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Install Java and Hadoop Clients
unless node['cdap'].key?('skip_prerequisites') && node['cdap']['skip_prerequisites'].to_s == 'true'
  include_recipe 'cdap::prerequisites'
end

include_recipe 'cdap::repo'

# add global CDAP_HOME environment variable
file '/etc/profile.d/cdap_home.sh' do
  content <<-EOS
    export CDAP_HOME=/opt/cdap
    export PATH=$PATH:$CDAP_HOME/bin
  EOS
  mode '0755'
end

package 'cdap' do
  version node['cdap']['version']
  action :install
end

if node['cdap'].key?('cdap_env') && node['cdap']['cdap_env'].key?('log_dir')
  cdap_log_dir =
    if node['cdap']['cdap_env'].key?('log_dir')
      node['cdap']['cdap_env']['log_dir']
    else
      '/var/log/cdap'
    end

  directory cdap_log_dir do
    owner 'cdap'
    group 'cdap'
    mode '0755'
    action :create
    recursive true
    only_if { node['cdap']['cdap_env'].key?('log_dir') }
  end

  unless cdap_log_dir == '/var/log/cdap'
    # Delete default directory, if we aren't set to it
    directory '/var/log/cdap' do
      action :delete
      not_if 'test -L /var/log/cdap'
    end
    # symlink
    link '/var/log/cdap' do
      to cdap_log_dir
    end
  end
end

include_recipe 'cdap::config'

if node['cdap'].key?('cdap_site') && node['cdap']['cdap_site'].key?('security.enabled') &&
   node['cdap']['cdap_site'].key?('security.auth.server.address') &&
   node['cdap']['cdap_site']['security.auth.server.address'] == node['fqdn']

  include_recipe 'cdap::security'
end
