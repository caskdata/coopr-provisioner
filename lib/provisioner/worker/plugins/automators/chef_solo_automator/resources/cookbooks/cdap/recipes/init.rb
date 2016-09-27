#
# Cookbook Name:: cdap
# Recipe:: init
#
# Copyright © 2013-2016 Cask Data, Inc.
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

# We also need the configuration, so we can run HDFS commands
# Retries allow for orchestration scenarios where HDFS is starting up
ns_path = node['cdap']['cdap_site']['hdfs.namespace']
hdfs_user = node['cdap']['cdap_site']['hdfs.user']
# Workaround for CDAP-3817, by pre-creating the transaction service snapshot directory
tx_snapshot_dir =
  if node['cdap']['cdap_site'].key?('data.tx.snapshot.dir')
    node['cdap']['cdap_site']['data.tx.snapshot.dir']
  else
    "#{ns_path}/tx.snapshot"
  end
user_path = "/user/#{hdfs_user}"

%W(#{ns_path} #{tx_snapshot_dir} #{user_path}).each do |path|
  execute "initaction-create-hdfs-path#{path.tr('/', '-')}" do
    command "hadoop fs -mkdir -p #{path} && hadoop fs -chown #{hdfs_user} #{path}"
    not_if "hadoop fs -test -d #{path}", :user => hdfs_user
    timeout 300
    user node['cdap']['fs_superuser']
    retries 3
    retry_delay 10
  end
end

%w(cdap yarn mapr).each do |u|
  %w(done done_intermediate).each do |dir|
    execute "initaction-create-hdfs-mr-jhs-staging-#{dir.tr('_', '-')}-#{u}" do
      only_if "getent passwd #{u}"
      not_if "hadoop fs -test -d /tmp/hadoop-yarn/staging/history/#{dir}/#{u}", :user => u
      command "hadoop fs -mkdir -p /tmp/hadoop-yarn/staging/history/#{dir}/#{u} && hadoop fs -chown #{u} /tmp/hadoop-yarn/staging/history/#{dir}/#{u} && hadoop fs -chmod 1777 /tmp/hadoop-yarn/staging/history/#{dir}/#{u}"
      timeout 300
      user node['cdap']['fs_superuser']
      retries 3
      retry_delay 10
    end
  end
end
