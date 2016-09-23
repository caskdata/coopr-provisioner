#!/usr/bin/env ruby
# encoding: UTF-8
#
# Copyright © 2012-2015 Cask Data, Inc.
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

require 'net/scp'
require 'deep_merge/rails_compat'
require 'base64'
require 'fileutils'

require_relative '../logging'

module Coopr
  module Plugin
    module Utils
      # Exception class used to return remote command stderr
      class CommandExecutionError < RuntimeError
        attr_reader :command, :stdout, :stderr, :exit_code, :exit_signal

        def initialize(command, stdout, stderr, exit_code, exit_signal)
          @command = command
          @stdout = stdout
          @stderr = stderr
          @exit_code = exit_code
          @exit_signal = exit_signal
        end

        def to_json(*a)
          result = {
            'message' => message,
            'command' => command,
            'stdout' => @stdout,
            'stderr' => @stderr,
            'exit_code' => @exit_code,
            'exit_signal' => @exit_signal
          }
          result.to_json(*a)
        end
      end

      # Decodes a base64 string into a file
      def decode_string_to_file(string, outfile, mode = 0o600)
        ::FileUtils.mkdir_p(::File.dirname(outfile))
        ::File.open(outfile, 'wb', mode) { |f| f.write(::Base64.decode64(string)) }
      end

      # Writes out an SSH file, given a path and task JSON, returns fully-qualified path to file
      def write_ssh_file(path, task)
        ssh_keyfile = task['config']['provider']['provisioner']['ssh_keyfile'] || nil
        identityfile = ::File.join(path, task['taskId'])
        log.debug "Writing out SSH private key to #{identityfile}" unless ssh_keyfile.nil?
        decode_string_to_file(ssh_keyfile, identityfile) unless ssh_keyfile.nil?
      end

      # Gets a host's SSH host key
      def ssh_keyscan(host, type = 'rsa')
        keytype = type == 'dsa' ? 'dss' : type
        # TODO: find a way to do this in Ruby
        key = `ssh-keyscan -t #{type} #{host} 2>&1 | grep #{keytype}`.split(' ')
        # Bad key type == "unknown key type #{type}"
        raise "Unknown SSH Key Type: #{type}" if key[2] == 'type' || key[2].nil?
        key[2]
      end

      # Utility method to run a command over ssh
      def ssh_exec!(ssh, command, message = command, pty = false)
        stdout_data = ''
        stderr_data = ''
        exit_code = nil
        exit_signal = nil
        log.debug message if message != command
        log.debug "---ssh-exec command: #{command}"
        ssh.open_channel do |channel|
          if pty
            channel.request_pty do |_ch, success|
              raise 'no pty!' unless success
            end
          end
          channel.exec(command) do |_ch, success|
            unless success
              abort "FAILED: couldn't execute command (ssh.channel.exec)"
            end
            channel.on_data do |_ch, data|
              stdout_data += data
            end

            channel.on_extended_data do |_ch, _type, data|
              stderr_data += data
            end

            channel.on_request('exit-status') do |_ch, data|
              exit_code = data.read_long
            end

            channel.on_request('exit-signal') do |_ch, data|
              exit_signal = data.read_long
            end
          end
        end
        ssh.loop

        log.debug "stderr: #{stderr_data}"
        log.debug "stdout: #{stdout_data}"

        raise CommandExecutionError.new(command, stdout_data, stderr_data, exit_code, exit_signal), message unless exit_code.zero?

        [stdout_data, stderr_data, exit_code, exit_signal]
      end
    end
  end
end
