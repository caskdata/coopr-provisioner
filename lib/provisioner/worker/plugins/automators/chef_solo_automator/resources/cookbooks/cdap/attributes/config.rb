#
# Cookbook Name:: cdap
# Attribute:: config
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

# Default: conf.chef
default['cdap']['conf_dir'] = 'conf.chef'
# Default: 3.5.1-1
default['cdap']['version'] = '3.5.1-1'
# cdap-site.xml
default['cdap']['cdap_site']['root.namespace'] = 'cdap'
# ideally we could put the macro '/${cdap.namespace}' here but this attribute is used elsewhere in the cookbook
default['cdap']['cdap_site']['hdfs.namespace'] = "/#{node['cdap']['cdap_site']['root.namespace']}"
default['cdap']['cdap_site']['hdfs.user'] = 'yarn'
default['cdap']['cdap_site']['kafka.seed.brokers'] = "#{node['fqdn']}:9092"
# CDAP 3.5.0 deprecated Kafka Server settings
if node['cdap']['version'].to_f < 3.5
  default['cdap']['cdap_site']['kafka.log.dir'] = '/data/cdap/kafka-logs'
  default['cdap']['cdap_site']['kafka.default.replication.factor'] = '1'
else
  default['cdap']['cdap_site']['kafka.server.log.dirs'] = '/data/cdap/kafka-logs'
  default['cdap']['cdap_site']['kafka.server.default.replication.factor'] = '1'
end
default['cdap']['cdap_site']['log.retention.duration.days'] = '7'
default['cdap']['cdap_site']['zookeeper.quorum'] = "#{node['fqdn']}:2181/#{node['cdap']['cdap_site']['root.namespace']}"
default['cdap']['cdap_site']['router.bind.address'] = node['fqdn']
default['cdap']['cdap_site']['router.server.address'] = node['fqdn']
default['cdap']['cdap_site']['app.bind.address'] = node['fqdn']
default['cdap']['cdap_site']['data.tx.bind.address'] = node['fqdn']
default['cdap']['cdap_site']['metrics.query.bind.address'] = node['fqdn']
default['cdap']['cdap_site']['dashboard.bind.port'] = '9999'
default['cdap']['cdap_site']['log.saver.run.memory.megs'] = '512'
# These are only used with CDAP < 2.6
if node['cdap']['version'].to_f < 2.6
  default['cdap']['cdap_site']['gateway.server.address'] = node['fqdn']
  default['cdap']['cdap_site']['gateway.server.port'] = '10000'
  default['cdap']['cdap_site']['gateway.memory.mb'] = '512'
end

# HDP 2.2+ support
hdp_version =
  if node.key?('hadoop') && node['hadoop'].key?('distribution_version')
    case node['hadoop']['distribution_version']
    when '2.2.0.0'
      '2.2.0.0-2041'
    when '2.2.1.0'
      '2.2.1.0-2340'
    when '2.2.4.2'
      '2.2.4.2-2'
    when '2.2.4.4'
      '2.2.4.4-16'
    when '2.2.6.0'
      '2.2.6.0-2800'
    when '2.2.8.0'
      '2.2.8.0-3150'
    when '2.2.9.0'
      '2.2.9.0-3393'
    when '2.3.0.0'
      '2.3.0.0-2557'
    when '2.3.2.0'
      '2.3.2.0-2950'
    when '2.3.4.0'
      '2.3.4.0-3485'
    when '2.3.4.7'
      '2.3.4.7-4'
    when '2.4.0.0'
      '2.4.0.0-169'
    when '2.4.2.0'
      '2.4.2.0-258'
    when '2.5.0.0'
      '2.5.0.0-1245'
    else
      node['hadoop']['distribution_version']
    end
  end

if node.key?('hadoop') && node['hadoop'].key?('distribution') && node['hadoop'].key?('distribution_version')
  if node['hadoop']['distribution'] == 'hdp' && node['hadoop']['distribution_version'].to_f >= 2.2 &&
     node['cdap']['version'].to_f >= 3.1
    default['cdap']['cdap_env']['opts'] = "${OPTS} -Dhdp.version=#{hdp_version}"
    default['cdap']['cdap_site']['app.program.jvm.opts'] = "-XX:MaxPermSize=128M ${twill.jvm.gc.opts} -Dhdp.version=#{hdp_version} -Dspark.yarn.am.extraJavaOptions=-Dhdp.version=#{hdp_version}"
    if node['cdap']['version'].to_f < 3.4
      default['cdap']['cdap_env']['spark_home'] = "/usr/hdp/#{hdp_version}/spark"
    end
  elsif node['hadoop']['distribution'] == 'iop'
    iop_version = node['hadoop']['distribution_version']
    default['cdap']['cdap_env']['opts'] = "${OPTS} -Diop.version=#{iop_version}"
    default['cdap']['cdap_site']['app.program.jvm.opts'] = "-XX:MaxPermSize=128M ${twill.jvm.gc.opts} -Diop.version=#{iop_version} -Dspark.yarn.am.extraJavaOptions=-Diop.version=#{iop_version}"
  elsif node['cdap']['version'].to_f < 3.4 # CDAP 3.4 determines SPARK_HOME on its own (CDAP-5086)
    default['cdap']['cdap_env']['spark_home'] = '/usr/lib/spark'
  end
end
