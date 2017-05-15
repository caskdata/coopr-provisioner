#!/usr/bin/env ruby
# encoding: UTF-8
#
# Copyright © 2012-2014 Cask Data, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'json'
require 'net/scp'
require 'base64'
require 'fileutils'
require 'rubygems/package'
require 'zlib'

class ChefSoloAutomator < Coopr::Plugin::Automator

  attr_accessor :credentials, :cookbooks_path, :cookbooks_tar, :remote_cache_dir

  # class vars
  @@chef_primitives = %w(cookbooks data_bags roles)
  @@remote_cache_dir = '/var/cache/coopr'
  @@remote_chef_dir = '/var/chef'

  # plugin defined resources
  @ssh_key_dir = 'ssh_keys'
  class << self
    attr_accessor :ssh_key_dir
  end

  # create local tarballs of the cookbooks, roles, data_bags, etc to be scp'd to remote machine
  def generate_chef_primitive_tar(chef_primitive)
    chef_primitive_path = "#{chef_primitive}"
    chef_primitive_tar = "#{chef_primitive}.tar.gz"

    # if no resources of this type are synced, dont do anything
    unless File.directory?(chef_primitive_path)
      log.warn "No resources of type #{chef_primitive_path} are synced, skipping tarball generation"
      return
    end

    # limit tarball regeneration to once per min
    # rubocop:disable GuardClause
    if !File.exist?(chef_primitive_tar) || ((Time.now - File.stat(chef_primitive_tar).mtime).to_i > 60)
      log.debug "Generating #{chef_primitive_tar} from #{chef_primitive_path}"
      `tar -chzf "#{chef_primitive_tar}.new" #{chef_primitive}`
      `mv "#{chef_primitive_tar}.new" "#{chef_primitive_tar}"`
      log.debug "Generation complete: #{chef_primitive_tar}"
    end
    # rubocop:enable GuardClause
  end

  def set_credentials(sshauth)
    @credentials = {}
    @credentials[:paranoid] = false
    sshauth.each do |k, v|
      if k =~ /identityfile/
        @credentials[:keys] = [v]
      elsif k =~ /password/
        @credentials[:password] = v
      end
    end
  end

  # generate the chef run json_attributes from the task metadata
  def generate_chef_json_attributes(servicestring)
    servicedata = Hash.new { |h, k| h[k] = Hash.new(&h.default_proc) }

    if servicestring.nil? || servicestring == ''
      servicestring = '{}'
    end
    # service data is passed here as an escaped json string
    servicedata.merge!(JSON.parse(servicestring))
    log.debug "Tasks before merging: #{@task}"

    # cluster and nodes data is passed as expanded hash
    clusterdata = @task['config']['cluster']
    if clusterdata.nil? || clusterdata == ''
      clusterdata = Hash.new { |h, k| h[k] = Hash.new(&h.default_proc) }
    end
    nodesdata = @task['config']['nodes']
    if nodesdata.nil? || nodesdata == ''
      nodesdata = Hash.new { |h, k| h[k] = Hash.new(&h.default_proc) }
    end

    # services is a list of services on this node
    node_services_data = @task['config']['services']
    if node_services_data.nil? || node_services_data == ''
      node_services_data = Hash.new { |h, k| h[k] = Hash.new(&h.default_proc) }
    end

    # Deep merge the service data into the cluster config data.  service data takes precedence
    clusterdata.deeper_merge!(servicedata)

    # merge data together into expected layout for json_attributes
    clusterdata['nodes'] = nodesdata
    servicedata['coopr']['cluster'] = clusterdata
    servicedata['coopr']['services'] = node_services_data

    # include additional node attributes not present in the cluster config
    servicedata['coopr']['hostname'] = @task['config']['hostname']
    servicedata['coopr']['clusterId'] = @task['clusterId']
    servicedata['coopr']['ipaddresses'] = @task['config']['ipaddresses']

    # we also need to merge cluster config top-level
    servicedata.merge!(clusterdata)

    # generate the json
    cooprdatajson = JSON.generate(servicedata)
    log.debug "Generated JSON attributes: #{cooprdatajson}"

    cooprdatajson
  end

  # bootstrap remote machine: install chef, copy all cookbooks, data_bags, etc in to place
  def bootstrap(inputmap)
    sshauth = inputmap['sshauth']
    hostname = inputmap['hostname']
    ipaddress = inputmap['ipaddress']

    # do we need sudo bash?
    sudo = 'sudo -E' unless sshauth['user'] == 'root'

    ssh_file = write_ssh_file(File.join(Dir.pwd, self.class.ssh_key_dir), @task)
    set_credentials(sshauth)

    @@chef_primitives.each do |chef_primitive|
      generate_chef_primitive_tar(chef_primitive)
    end

    log.debug "Attempting ssh into ip: #{ipaddress}, user: #{sshauth['user']}"
    install_chef(inputmap)

    begin
      Net::SSH.start(ipaddress, sshauth['user'], @credentials) do |ssh|
        ssh_exec!(ssh, "#{sudo} mkdir -p #{@@remote_cache_dir}", 'Create remote cache dir')
        # Create remote directories for all chef primitives, as some recipes can fail if for example data_bags directory is missing
        @@chef_primitives.each do |chef_primitive|
          ssh_exec!(ssh, "#{sudo} mkdir -p #{@@remote_chef_dir}/#{chef_primitive}", "Create remote Chef dir for #{chef_primitive}")
        end

        ssh_exec!(ssh, "#{sudo} chown -R #{sshauth['user']} #{@@remote_cache_dir}", "Changing cache dir owner to #{sshauth['user']}")
        ssh_exec!(ssh, "#{sudo} chown -R #{sshauth['user']} #{@@remote_chef_dir}", "Changing Chef dir owner to #{sshauth['user']}")
      end
    rescue Net::SSH::AuthenticationFailed => e
      raise $!, "SSH Authentication failure for #{ipaddress}: #{$!}", $!.backtrace
    end

    # check to ensure scp is installed and attempt to install it
    begin
      Net::SSH.start(ipaddress, sshauth['user'], @credentials) do |ssh|

        log.debug 'Checking for scp installation'
        begin
          ssh_exec!(ssh, 'which scp')
        rescue CommandExecutionError
          log.warn 'scp not found, attempting to install openssh-client'
          scp_install_cmd = "#{sudo} yum -q -y install openssh-clients"
          begin
            ssh_exec!(ssh, 'which yum')
          rescue CommandExecutionError
            scp_install_cmd = "#{sudo} apt-get -q -y install openssh-client"
          end
          ssh_exec!(ssh, scp_install_cmd, "installing openssh-client via #{scp_install_cmd}")
        else
          log.debug 'scp found on remote'
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      raise $!, "SSH Authentication failure for #{ipaddress}: #{$!}", $!.backtrace
    end

    # upload tarballs to target machine
    @@chef_primitives.each do |chef_primitive|
      next unless File.exist?("#{chef_primitive}.tar.gz")

      log.debug "Uploading #{chef_primitive} from #{chef_primitive}.tar.gz to #{ipaddress}:#{@@remote_cache_dir}/#{chef_primitive}.tar.gz"
      begin
        Net::SCP.upload!(ipaddress, sshauth['user'], "#{chef_primitive}.tar.gz", "#{@@remote_cache_dir}/#{chef_primitive}.tar.gz", :ssh =>
            @credentials)
      rescue Net::SSH::AuthenticationFailed => e
        raise $!, "SSH Authentication failure for #{ipaddress}: #{$!}", $!.backtrace
      end
      log.debug 'Upload complete'

      # extract tarballs on remote machine to /var/chef
      begin
        Net::SSH.start(ipaddress, sshauth['user'], @credentials) do |ssh|
          ssh_exec!(ssh, "tar xf #{@@remote_cache_dir}/#{chef_primitive}.tar.gz -C #{@@remote_chef_dir}", "Extracting remote #{@@remote_cache_dir}/#{chef_primitive}.tar.gz")
        end
      rescue Net::SSH::AuthenticationFailed => e
        raise $!, "SSH Authentication failure for #{ipaddress}: #{$!}", $!.backtrace
      end
    end

    @result['status'] = 0

    log.debug "ChefSoloAutomator bootstrap completed successfully: #{@result}"
    @result
  ensure
    File.delete(ssh_file) if ssh_file && File.exist?(ssh_file)
  end

  def runchef(inputmap)
    sshauth = inputmap['sshauth']
    ipaddress = inputmap['ipaddress']
    fields = inputmap['fields']

    fail "required parameter \"run_list\" not found in input: #{fields}" if fields['run_list'].nil?
    # run_list as specified by user
    run_list = fields['run_list']
    # whitespace in the runlist is not allowed
    run_list.gsub!(/\s+/, '')

    # additional json attributes defined for this service action
    json_attributes = fields['json_attributes']

    # merge together json_attributes, cluster config, coopr node data
    jsondata = generate_chef_json_attributes(json_attributes)

    # do we need sudo bash?
    sudo = 'sudo -E' unless sshauth['user'] == 'root'

    ssh_file = write_ssh_file(File.join(Dir.pwd, self.class.ssh_key_dir), @task)
    set_credentials(sshauth)

    begin
      # write json attributes to a local tmp file
      tmpjson = Tempfile.new('coopr')
      tmpjson.write(jsondata)
      tmpjson.close

      # scp task.json to remote
      log.debug 'Copying json attributes to remote'
      begin
        Net::SCP.upload!(ipaddress, sshauth['user'], tmpjson.path, "#{@@remote_cache_dir}/#{@task['taskId']}.json", :ssh =>
          @credentials)
      rescue Net::SSH::AuthenticationFailed
        raise $!, "SSH Authentication failure for #{ipaddress}: #{$!}", $!.backtrace
      end
      log.debug 'Copy json attributes complete'

    ensure
      tmpjson.close
      tmpjson.unlink
    end

    begin
      Net::SSH.start(ipaddress, sshauth['user'], @credentials) do |ssh|

        ssh_exec!(ssh, "#{sudo} chef-solo --no-color -j #{@@remote_cache_dir}/#{@task['taskId']}.json -o '#{run_list}'", 'Running Chef-solo')
      end
    rescue Net::SSH::AuthenticationFailed
      raise $!, "SSH Authentication failure for #{ipaddress}: #{$!}", $!.backtrace
    end

    @result['status'] = 0
    log.debug "Chef-solo run completed successfully for task #{@task['taskId']}: #{@result}"
    @result
  ensure
    File.delete(ssh_file) if ssh_file && File.exist?(ssh_file)
  end

  def install_chef(inputmap)
    sshauth = inputmap['sshauth']
    ipaddress = inputmap['ipaddress']

    # do we need sudo bash?
    sudo = 'sudo -E' unless sshauth['user'] == 'root'

    ssh_file = write_ssh_file(File.join(Dir.pwd, self.class.ssh_key_dir), @task)
    set_credentials(sshauth)

    begin
      Net::SSH.start(ipaddress, sshauth['user'], @credentials) do |ssh|
        begin
          # determine if Chef is installed
          ssh_exec!(ssh, 'which chef-solo', 'Checking if chef-solo is present')
          return
        rescue CommandExecutionError
          # no chef-solo, install it
          log.debug 'Installing Chef'
        end

        # try installing via package manager
        begin
          ssh_exec!(ssh, "which yum && #{sudo} yum -q -y install chef", 'Attempting Chef install via YUM')
          return
        rescue CommandExecutionError
          begin
            candidate_version = ssh_exec!(ssh, "#{sudo} apt-cache policy chef | grep Candidate | awk '{ print $2}'", 'Retrieving candidate Chef version').first.chomp
            log.debug "Found chef version #{candidate_version} available for install via package repositories"
            # Bundled cookbooks require Chef 12.1 or later
            if candidate_version.to_f >= 12.1
              ssh_exec!(ssh, "which apt-get && DEBIAN_FRONTEND=noninteractive #{sudo} apt-get -q -y install chef", 'Attempting Chef install via apt-get')
              return
            end
          rescue
            log.debug 'No Chef packages found for installation'
          end
        end

        # determine if curl is installed, else default to wget
        chef_version = '12.4.3'
        chef_install_cmd = "set -o pipefail && curl --fail -L https://omnitruck.chef.io/install.sh | #{sudo} bash -s -- -v #{chef_version}"
        begin
          ssh_exec!(ssh, 'which curl', 'Checking for curl')
        rescue CommandExecutionError
          log.debug 'curl not found, defaulting to wget'
          chef_install_cmd = "set -o pipefail && wget -qO - https://omnitruck.chef.io/install.sh | #{sudo} bash -s -- -v #{chef_version}"
        end
        ssh_exec!(ssh, chef_install_cmd, 'Installing Chef')
      end
    rescue
      raise 'Failed to install Chef'
    end
  ensure
    File.delete(ssh_file) if ssh_file && File.exist?(ssh_file)
  end

  def install(inputmap)
    log.debug "ChefSoloAutomator performing install task #{@task['taskId']}"
    runchef(inputmap)
  end

  def configure(inputmap)
    log.debug "ChefSoloAutomator performing configure task #{@task['taskId']}"
    runchef(inputmap)
  end

  def init(inputmap)
    log.debug "ChefSoloAutomator performing initialize task #{@task['taskId']}"
    runchef(inputmap)
  end

  def start(inputmap)
    log.debug "ChefSoloAutomator performing start task #{@task['taskId']}"
    runchef(inputmap)
  end

  def stop(inputmap)
    log.debug "ChefSoloAutomator performing stop task #{@task['taskId']}"
    runchef(inputmap)
  end

  def remove(inputmap)
    log.debug "ChefSoloAutomator performing remove task #{@task['taskId']}"
    runchef(inputmap)
  end
end
