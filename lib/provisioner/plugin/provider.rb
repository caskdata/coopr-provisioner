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

require_relative '../logging'
require_relative 'utils'

module Coopr
  module Plugin
    # Base class for all provider plugins.  This should be extended, not modified
    class Provider
      include Coopr::Logging
      include Coopr::Plugin::Utils
      attr_accessor :task, :flavor, :image, :hostname, :providerid, :result
      attr_reader :env
      def initialize(env, task)
        @task = task
        @env = env
        @result = Hash.new { |h, k| h[k] = Hash.new(&h.default_proc) }
      end

      def runTask
        case task['taskName'].downcase
        when 'create'
          create('flavor' => task['config']['flavor'], 'image' => task['config']['image'], 'hostname' => task['config']['hostname'], 'fields' => task['config']['provider']['provisioner'])
          @result
        when 'confirm'
          confirm('providerid' => task['config']['providerid'], 'fields' => task['config']['provider']['provisioner'])
          @result
        when 'delete'
          delete('providerid' => task['config']['providerid'], 'fields' => task['config']['provider']['provisioner'])
          @result
        else
          raise "unhandled provider task type: #{task['taskName']}"
        end
      end

      def create(_inputmap)
        @result['status'] = 1
        @result['message'] = "Unimplemented task create in class #{self.class.name}"
        # fields under 'result' will be passed to subsequent tasks
        @result['result']['providerid'] = 'exampleid'
        @result['result']['foo'] = 'bar'
        raise "Unimplemented task create in class #{self.class.name}"
      end

      def confirm(_inputmap)
        @result['status'] = 1
        @result['message'] = "Unimplemented task create in class #{self.class.name}"
        @result['result']['ipaddress'] = '1.2.3.4'
        raise "Unimplemented task confirm in class #{self.class.name}"
      end

      def delete(_inputmap)
        @result['status'] = 1
        @result['message'] = "Unimplemented task create in class #{self.class.name}"
        raise "Unimplemented task delete in class #{self.class.name}"
      end
    end
  end
end
