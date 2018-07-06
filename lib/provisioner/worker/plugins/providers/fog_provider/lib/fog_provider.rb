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

require_relative 'fog_provider/aws'
require_relative 'fog_provider/digitalocean'
require_relative 'fog_provider/google'
require_relative 'fog_provider/joyent'
require_relative 'fog_provider/openstack'
require_relative 'fog_provider/rackspace'

#gem 'fog', '~> 1.36.0'
#gem 'fog'
#gem 'google-api-client', '~> 0.8.0'
gem 'google-api-client'

#require 'fog'
gem 'fog-google'
require 'fog/google'
require 'ipaddr'
require 'net/ssh'
