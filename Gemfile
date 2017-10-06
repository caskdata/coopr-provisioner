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

source 'https://rubygems.org'

gem 'rake'

group :dependencies do
  # These gems are used by the provisioner
  gem 'deep_merge', '~> 1.0', require: 'deep_merge/rails_compat'
  gem 'json', '~> 1.7.7'
  gem 'logger'
  gem 'mime-types', '< 3.0'
  gem 'net-scp'
  gem 'public_suffix', '< 1.5.0' # ruby 1.9.3
  gem 'rest-client', '~> 1.7'
  gem 'retriable', '< 3.0.0' # ruby 1.9.3
  gem 'sinatra', '~> 1.4'
  gem 'thin', '~> 1.6'
end

group :test do
  gem 'rack-test', '~> 0.6'
  gem 'rspec', '~> 3.0'
  # rubocop: disable Lint/UnneededDisable
  # rubocop: disable Bundler/DuplicatedGem
  if RUBY_VERSION.to_f < 2.0
    gem 'rubocop', '< 0.42'
  else
    gem 'rubocop', '~> 0.24'
  end
  # rubocop: enable Bundler/DuplicatedGem
  # rubocop: enable Lint/UnneededDisable
  gem 'simplecov', '~> 0.7.1', require: false
end

# Install gems from each plugin
Dir.glob(File.join(File.dirname(__FILE__), 'lib', 'provisioner', 'worker', 'plugins', '*', '*', 'Gemfile')) do |gemfile|
  puts "Including provisioner plugin Gemfile: #{gemfile}"
  eval_gemfile(gemfile)
end
