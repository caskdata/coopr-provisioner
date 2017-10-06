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

require 'rest-client'
require 'openssl'

module Coopr
  class RestHelper
    @cert_path = nil
    @cert_pass = nil

    class << self
      attr_writer :cert_path
    end

    class << self
      attr_writer :cert_pass
    end

    def self.get_resource(uri)
      if @cert_path.nil? || @cert_path.empty?
        RestClient::Resource.new(uri)
      else
        cert = File.read(@cert_path)
        RestClient::Resource.new(
          uri,
          ssl_client_cert: OpenSSL::X509::Certificate.new(cert),
          ssl_client_key: OpenSSL::PKey::RSA.new(cert, @cert_pass)
        )
      end
    end

    def self.get(uri, headers = {})
      resource = get_resource(uri)
      resource.get(headers)
    end

    def self.post(uri, payload, headers = {})
      resource = get_resource(uri)
      resource.post(payload, headers)
    end

    def self.put(uri, payload, headers = {})
      resource = get_resource(uri)
      resource.put(payload, headers)
    end

    def self.delete(uri, headers = {})
      resource = get_resource(uri)
      resource.delete(headers)
    end
  end
end
