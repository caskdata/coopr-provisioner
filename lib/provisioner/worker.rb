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
require 'optparse'
require 'rest_client'
require 'socket'
require 'logger'
require 'fileutils'

require_relative 'worker/utils'
require_relative 'worker/pluginmanager'
require_relative 'worker/provider'
require_relative 'worker/automator'
require_relative 'worker/cli'
require_relative 'rest-helper'

require_relative 'config'
require_relative 'logging'
require_relative 'constants'


$stdout.sync = true

module Coopr
  class Worker
    include Logging

    # Passed in options and configuration
    attr_reader :options, :config

    # Options that must be passed (cmdline) or set (by master)
    attr_accessor :tenant, :file, :provisioner_id, :name, :register, :once

    def initialize(options, config)
      @options = options
      @config = config

      # Log configuration
      log.debug 'Provisioner starting up'
      config.properties.each do |k, v|
        log.debug "  #{k}: #{v}"
      end

      # Process options, only in case of cmdline startup
      log.debug 'Cmdline options' unless options.empty?
      options.each do |k, v|
        instance_variable_set("@#{k}", v)
        log.debug "  #{k}: #{v}"
      end

      # Initialize PluginManager
      @pluginmanager = Coopr::Worker::PluginManager.new

    end

    # Cmdline entry point
    def self.run(options)
      # Read configuration xml
      config = Coopr::Config.new(options)
      require 'pp'
      pp config
      config.load
      # initialize logging
      Coopr::Logging.configure(config.get(PROVISIONER_LOG_DIR) ? "#{config.get(PROVISIONER_LOG_DIR)}/provisioner.log" : nil)
      Coopr::Logging.level = config.get(PROVISIONER_LOG_LEVEL)
      Coopr::Logging.shift_age = config.get(PROVISIONER_LOG_ROTATION_SHIFT_AGE)
      Coopr::Logging.shift_size = config.get(PROVISIONER_LOG_ROTATION_SHIFT_SIZE)

      worker = Coopr::Worker.new(options, config)
      if options[:register]
        worker.register_plugins
      elsif options[:file]
        #worker.run_task_from_file
      else
        #worker.work
      end
    end

    # Register plugins with the server
    def register_plugins
      @pluginmanager.register_plugins(@config.get(PROVISIONER_SERVER_URI))
      if @pluginmanager.load_errors?
        log.error 'There was at least one provisioner plugin load failure'
        exit(1)
      end
      if @pluginmanager.register_errors?
        log.error 'There was at least one provisioner plugin register failure'
        exit(1)
      end
      exit(0)
    end
  end
end



__END__



Coopr::RestHelper.cert_path = options[:cert_path]
Coopr::RestHelper.cert_pass = options[:cert_pass]


include Logging
log_file = nil
if options[:log_directory] && options[:name]
  log_file = [options[:log_directory], options[:name]].join('/') + '.log'
elsif options[:log_directory]
  log_file = "#{options[:log_directory]}/worker-default.log"
end
Logging.configure(log_file)
Logging.level = options[:log_level]
Logging.process_name = options[:name] if options[:name]

# load plugins
pluginmanager = PluginManager.new

# ensure we have at least one plugin of each type for task coverage
if pluginmanager.providermap.empty? or pluginmanager.automatormap.empty?
  log.fatal 'Error: at least one provider plugin and one automator plugin must be installed'
  exit(1)
end

# the environment passed to plugins
@plugin_env = options

def _run_plugin(clazz, env, cwd, task)
  clusterId = task['clusterId']
  hostname = task['config']['hostname']
  provider = task['config']['provider']['description']
  imagetype = task['config']['imagetype']
  hardware = task['config']['hardwaretype']
  taskName = task['taskName'].downcase
  log.info "Creating node #{hostname} on #{provider} for #{clusterId} using #{imagetype} on #{hardware}" if taskName == 'create'

  object = clazz.new(env, task)
  FileUtils.mkdir_p(cwd)
  Dir.chdir(cwd) do
    result = object.runTask
    log.info "#{clusterId} on #{hostname} could not be deleted: #{result['message']}" if taskName == 'delete' && result['status'] != 0
    result
  end
end

def delegate_task(task, pluginmanager)
  providerName = nil # rubocop:disable UselessAssignment
  automatorName = nil # rubocop:disable UselessAssignment
  clazz = nil # rubocop:disable UselessAssignment
  object = nil
  result = nil
  classes = nil
  task_id = task['taskId']

  log.debug "Processing task with id #{task_id} ..."

  taskName = task['taskName'].downcase
  # depending on task, these may be nil
  # automator take pecedence as presence indicates a 'software' task
  providerName = task['config']['provider']['providertype'] rescue nil
  automatorName = task['config']['service']['action']['type'] rescue nil

  case taskName.downcase
  when 'create', 'confirm', 'delete'
    clazz = Object.const_get(pluginmanager.getHandlerActionObjectForProvider(providerName))
    cwd = File.join(@plugin_env[:work_dir], @plugin_env[:tenant], 'providertypes', providerName)
    result = _run_plugin(clazz, @plugin_env, cwd, task)
  when 'install', 'configure', 'initialize', 'start', 'stop', 'remove'
    clazz = Object.const_get(pluginmanager.getHandlerActionObjectForAutomator(automatorName))
    cwd = File.join(@plugin_env[:work_dir], @plugin_env[:tenant], 'automatortypes', automatorName)
    result = _run_plugin(clazz, @plugin_env, cwd, task)
  when 'bootstrap'
    combinedresult = {}
    classes = []
    if task['config'].key? 'automators' and !task['config']['automators'].empty?
      # server must specify which bootstrap handlers need to run
      log.debug "Task #{task_id} running specified bootstrap handlers: #{task['config']['automators']}"
      task['config']['automators'].each do |automator|
        clazz = Object.const_get(pluginmanager.getHandlerActionObjectForAutomator(automator))
        cwd = File.join(@plugin_env[:work_dir], @plugin_env[:tenant], 'automatortypes', automator)
        result = _run_plugin(clazz, @plugin_env, cwd, task)
        combinedresult.merge!(result)
      end
    else
      log.warn 'No automators specified to bootstrap'
    end
    result = combinedresult
  else
    log.error "Unhandled task of type #{task['taskName']}"
    fail "Unhandled task of type #{task['taskName']}"
  end
  result
end




log.debug "provisioner starting with provider types: #{pluginmanager.providermap.keys}"
log.debug "provisioner starting with automator types: #{pluginmanager.automatormap.keys}"

if options[:file]
  # run a single task read from file
  begin
    result = nil
    task = nil
    log.info "Start Provisioner run for file #{options[:file]}"
    task = JSON.parse(IO.read(options[:file]))

    # While provisioning, don't allow the provisioner to terminate by disabling signal
    sigterm = SignalHandler.new('TERM')
    sigterm.dont_interupt {
      result = delegate_task(task, pluginmanager)
    }
  rescue => e
    log.error "Caught exception when running task from file #{options[:file]}"

    result = {} if result.nil? == true
    result['status'] = '1'
    if e.class.name == 'CommandExecutionError'
      log.error "#{e.class.name}: #{e.to_json}"
      result['stdout'] = e.stdout
      result['stderr'] = e.stderr
    else
      result['stdout'] = e.inspect
      result['stderr'] = "#{e.inspect}\n#{e.backtrace.join("\n")}"
    end
    log.error "Provisioner run failed, result: #{result}"
  end
else
  # run in server polling mode

  pid = Process.pid
  host = Socket.gethostname.downcase
  myid = "#{host}.#{pid}"

  log.info "Starting provisioner with id #{myid}, connecting to server #{coopr_uri}"

  loop {
    result = nil
    response = nil
    task = nil
    begin
      response = Coopr::RestHelper.post "#{coopr_uri}/v2/tasks/take", { 'provisionerId' => options[:provisioner], 'workerId' => myid, 'tenantId' => options[:tenant] }.to_json
    rescue => e
      log.error "Caught exception connecting to coopr server #{coopr_uri}/v2/tasks/take: #{e}"
      sleep 10
      next
    end

    begin
      if response.code == 200 && response.to_str && response.to_str != ''
        task = JSON.parse(response.to_str)
        log.debug "Received task from server <#{response.to_str}>"
      elsif response.code == 204
        break if options[:once]
        sleep 1
        next
      else
        log.error "Received error code #{response.code} from coopr server: #{response.to_str}"
        sleep 10
        next
      end
    rescue => e
      log.error "Caught exception processing response from coopr server: #{e.inspect}"
    end

    # While provisioning, don't allow the provisioner to terminate by disabling signal
    sigterm = SignalHandler.new('TERM')
    sigterm.dont_interupt {
      begin
        result = delegate_task(task, pluginmanager)

        result = Hash.new if result.nil? == true
        result['workerId'] = myid
        result['taskId'] = task['taskId']
        result['provisionerId'] = options[:provisioner]
        result['tenantId'] = options[:tenant]

        log.debug "Task <#{task['taskId']}> completed, updating results <#{result}>"
        begin
          response = Coopr::RestHelper.post "#{coopr_uri}/v2/tasks/finish", result.to_json
        rescue => e
          log.error "Caught exception posting back to coopr server #{coopr_uri}/v2/tasks/finish: #{e}"
        end

      rescue => e
        result = Hash.new if result.nil? == true
        result['status'] = '1'
        result['workerId'] = myid
        result['taskId'] = task['taskId']
        result['provisionerId'] = options[:provisioner]
        result['tenantId'] = options[:tenant]
        if e.class.name == 'CommandExecutionError'
          log.error "#{e.class.name}: #{e.to_json}"
          result['stdout'] = e.stdout
          result['stderr'] = e.stderr
        else
          result['stdout'] = e.inspect
          result['stderr'] = "#{e.inspect}\n#{e.backtrace.join("\n")}"
        end
        log.error "Task <#{task['taskId']}> failed, updating results <#{result}>"
        begin
          response = Coopr::RestHelper.post "#{coopr_uri}/v2/tasks/finish", result.to_json
        rescue => e
          log.error "Caught exception posting back to server #{coopr_uri}/v2/tasks/finish: #{e}"
        end
      end
    }

    break if options[:once]
    sleep 5
  }

end